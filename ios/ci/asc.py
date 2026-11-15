#!/usr/bin/env python3
"""App Store Connect API 手工签名小工具（CI 专用）。

为什么要它
----------
`ios/project.yml` 生成的工程在 CI 里走「自动签名」永远会失败：

    error: Your team has no devices from which to generate a provisioning profile.
    error: No profiles for 'com.realsuntime.solartime' were found ... iOS App Development

因为个人开发者账号下**一个已注册设备都没有**，xcodebuild 只会去申请
*iOS App Development* 描述文件，而 Development 描述文件必须绑设备。
硬塞 `CODE_SIGN_IDENTITY="Apple Distribution"` 又会被判成设置冲突
（Run #3：conflicting provisioning settings）。

换一条死不了的路：**手工签名**。App Store 分发用的两样东西都不需要设备：

    Apple Distribution 证书      POST /v1/certificates  (certificateType=DISTRIBUTION)
    IOS_APP_STORE 描述文件       POST /v1/profiles      (profileType=IOS_APP_STORE)

本脚本负责这两步 + 只读诊断。签名用的 `.p12` / 钥匙串导入由工作流里的
openssl + security 完成（见 .github/workflows/ios-testflight.yml）。

子命令
------
  preflight   只读诊断：App 记录、Bundle ID、证书、描述文件、设备
  signing     申请 Apple Distribution 证书 + IOS_APP_STORE 描述文件并落地
  selfcheck   本地自检（不联网）：JWT 签名、CSR、PEM 编解码

依赖：cryptography、PyJWT
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import shlex
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
PROFILE_DIR = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")


class AscError(RuntimeError):
    pass


# ----------------------------------------------------------------- 鉴权

def make_token(key_id: str, issuer_id: str, key_path: str, ttl: int = 1200) -> str:
    """用 AuthKey_XXXX.p8（ES256）签一个 App Store Connect API Token。"""
    import jwt  # PyJWT

    with open(key_path, "r", encoding="utf-8") as fh:
        private_key = fh.read()
    now = int(time.time())
    claims = {
        "iss": issuer_id,
        # 往前挪 30 秒，抵消 runner 与 Apple 的时钟差
        "iat": now - 30,
        "exp": now + ttl,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(claims, private_key, algorithm="ES256", headers={"kid": key_id})


# ----------------------------------------------------------------- HTTP

def api(method: str, path: str, token: str, *, payload=None, params=None, tolerate=()):
    url = path if path.startswith("http") else API + path
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(
            params, doseq=True, safe="[],:@"
        )
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    body = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", "replace")
        if exc.code in tolerate:
            print(f"[warn] {method} {url} -> HTTP {exc.code}: {raw[:400]}", file=sys.stderr)
            return {"__error__": {"status": exc.code, "body": raw}}
        raise AscError(f"{method} {url} -> HTTP {exc.code}\n{raw}") from None
    except urllib.error.URLError as exc:
        raise AscError(f"{method} {url} -> 网络错误: {exc}") from None


def list_all(path: str, token: str, params: dict | None = None, cap: int = 500) -> list[dict]:
    out: list[dict] = []
    query = dict(params or {})
    query.setdefault("limit", "200")
    url = path
    while url:
        data = api("GET", url, token, params=query)
        out.extend(data.get("data") or [])
        nxt = (data.get("links") or {}).get("next")
        if not nxt or len(out) >= cap:
            break
        url, query = nxt, None
    return out


# ----------------------------------------------------------------- 小工具

def env_write(pairs: dict[str, str]) -> None:
    """写进 $GITHUB_ENV，后续 step 直接用。"""
    target = os.environ.get("GITHUB_ENV")
    if not target:
        return
    with open(target, "a", encoding="utf-8") as fh:
        for k, v in pairs.items():
            fh.write(f"{k}={v}\n")


def dump_signing_env(path: str, pairs: dict[str, str]) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        for k, v in pairs.items():
            fh.write(f"{k}={shlex.quote(v)}\n")


def fmt_cert(c: dict) -> str:
    a = c.get("attributes") or {}
    return (f"  - id={c['id']} type={a.get('certificateType')} "
            f"expires={a.get('expirationDate')} name={(a.get('displayName') or a.get('name') or '')}")


def has_phrase(exc: Exception, *phrases: str) -> bool:
    text = str(exc).lower()
    return any(p.lower() in text for p in phrases)


# ----------------------------------------------------------------- preflight

def cmd_preflight(args, token: str) -> int:
    print("=" * 70)
    print("App Store Connect 只读诊断")
    print("=" * 70)

    report: dict = {"bundleId": args.bundle_id}

    apps = list_all("/v1/apps", token, {"filter[bundleId]": args.bundle_id})
    report["apps"] = [
        {
            "id": a["id"],
            "name": (a.get("attributes") or {}).get("name"),
            "sku": (a.get("attributes") or {}).get("sku"),
            "bundleId": (a.get("attributes") or {}).get("bundleId"),
        }
        for a in apps
    ]
    print(f"\n[1/5] App 记录（/v1/apps，filter[bundleId]={args.bundle_id}）："
          f"{len(report['apps'])} 条")
    for a in report["apps"]:
        print(f"  - id={a['id']} name={a['name']!r} sku={a['sku']!r} bundleId={a['bundleId']}")
    if not report["apps"]:
        print("  !! 没有 App 记录 —— 构建可以上传但会被拒："
              "No suitable application records were found")
        print("     需要在 https://appstoreconnect.apple.com/apps 网页上新建 App。")

    bids = list_all("/v1/bundleIds", token, {"filter[identifier]": args.bundle_id})
    report["bundleIds"] = [
        {"id": b["id"], "identifier": (b.get("attributes") or {}).get("identifier"),
         "name": (b.get("attributes") or {}).get("name")}
        for b in bids
    ]
    print(f"\n[2/5] Bundle ID 注册（/v1/bundleIds）：{len(report['bundleIds'])} 条")
    for b in report["bundleIds"]:
        print(f"  - id={b['id']} identifier={b['identifier']} name={b['name']!r}")

    certs = list_all("/v1/certificates", token)
    report["certificates"] = [
        {"id": c["id"], "type": (c.get("attributes") or {}).get("certificateType"),
         "expires": (c.get("attributes") or {}).get("expirationDate")}
        for c in certs
    ]
    dist = [c for c in certs
            if (c.get("attributes") or {}).get("certificateType") == "DISTRIBUTION"]
    print(f"\n[3/5] 证书（/v1/certificates）：共 {len(certs)} 张，其中 Distribution {len(dist)} 张")
    for c in certs:
        print(fmt_cert(c))

    profiles = list_all("/v1/profiles", token)
    report["profiles"] = [
        {"id": p["id"], "name": (p.get("attributes") or {}).get("name"),
         "type": (p.get("attributes") or {}).get("profileType"),
         "uuid": (p.get("attributes") or {}).get("uuid"),
         "state": (p.get("attributes") or {}).get("profileState")}
        for p in profiles
    ]
    print(f"\n[4/5] 描述文件（/v1/profiles）：{len(profiles)} 条")
    for p in report["profiles"]:
        print(f"  - id={p['id']} type={p['type']} name={p['name']!r} uuid={p['uuid']} state={p['state']}")

    devices = list_all("/v1/devices", token)
    report["devices"] = [d["id"] for d in devices]
    print(f"\n[5/5] 已注册设备（/v1/devices）：{len(devices)} 台")
    for d in devices:
        a = d.get("attributes") or {}
        print(f"  - {a.get('name')!r} {a.get('udid')} {a.get('platform')}/{a.get('deviceClass')}")
    if not devices:
        print("  !! 0 台设备 —— 这正是不该再走「自动签名」的原因（见 Run #2 日志）")

    report["hasAppRecord"] = bool(report["apps"])
    report["hasBundleId"] = bool(report["bundleIds"])
    print("\n结论：App 记录 %s / Bundle ID %s / 设备 %d 台"
          % ("存在" if report["hasAppRecord"] else "缺失",
             "已注册" if report["hasBundleId"] else "未注册",
             len(devices)))

    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(report, fh, ensure_ascii=False, indent=2)
        print(f"（报告已写入 {args.json_out}）")

    env_write({
        "HAS_APP_RECORD": "yes" if report["hasAppRecord"] else "no",
        "HAS_BUNDLE_ID": "yes" if report["hasBundleId"] else "no",
    })
    return 0


# ----------------------------------------------------------------- signing

def _gen_key_and_csr(common_name: str):
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID

    # Apple 的分发证书仍然按 RSA 2048 收（fastlane cert 同款参数）
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)]))
        .sign(key, hashes.SHA256())
    )
    key_pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode("ascii")
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode("ascii")
    return key_pem, csr_pem, key


def unwrap(resp: dict) -> dict:
    """POST/PATCH 的响应长这样：{"data": {"type": ..., "id": ..., "attributes": {...}}}"""
    if isinstance(resp, dict) and isinstance(resp.get("data"), dict):
        return resp["data"]
    return resp


def _create_cert(token: str, csr_pem: str) -> dict:
    payload = {
        "data": {
            "type": "certificates",
            "attributes": {"certificateType": "DISTRIBUTION", "csrContent": csr_pem},
        }
    }
    return unwrap(api("POST", "/v1/certificates", token, payload=payload))


def _distribution_certs(token: str) -> list[dict]:
    return list_all("/v1/certificates", token, {"filter[certificateType]": "DISTRIBUTION"})


def cmd_signing(args, token: str) -> int:
    from cryptography import x509
    from cryptography.hazmat.primitives import serialization

    print("=" * 70)
    print("申请 Apple Distribution 证书 + IOS_APP_STORE 描述文件")
    print("=" * 70)

    # 1) Bundle ID 必须在开发者后台注册过（本项目已注册）
    bids = list_all("/v1/bundleIds", token, {"filter[identifier]": args.bundle_id})
    if not bids:
        raise AscError(
            f"Bundle ID {args.bundle_id} 没有在开发者后台注册。\n"
            "请到 https://developer.apple.com/account/resources/identifiers 注册后重跑。"
        )
    bid_id = bids[0]["id"]
    print(f"[1/4] Bundle ID 就绪：{args.bundle_id}（id={bid_id}）")

    # 2) 私钥 + CSR
    key_pem, csr_pem, key = _gen_key_and_csr(args.bundle_id)
    print("[2/4] 已生成 RSA 2048 私钥与 CSR")

    # 3) 申请分发证书。个人账号的分发证书有配额，Apple 会回
    #    "You already have a current Distribution certificate ..."，
    #    这时吊销最早到期的那张（都是本仓库 CI 之前建的，没有本地私钥也用不了）再重试。
    created = None
    last_error: Exception | None = None
    for attempt in range(1, 6):
        try:
            created = _create_cert(token, csr_pem)
            print(f"[3/4] 第 {attempt} 次申请成功：certificate id={created['id']}")
            break
        except AscError as exc:
            last_error = exc
            if not has_phrase(exc, "already have", "maximum", "limit", "reached"):
                raise
            existing = _distribution_certs(token)
            if not existing:
                raise
            # 最早到期的先吊销（Apple 的到期时间与创建时间同序）
            existing.sort(key=lambda c: (c.get("attributes") or {}).get("expirationDate") or "")
            victim = existing[0]
            print(f"[3/4] 配额已满，吊销旧分发证书 id={victim['id']} "
                  f"expires={(victim.get('attributes') or {}).get('expirationDate')}")
            api("DELETE", f"/v1/certificates/{victim['id']}", token, tolerate=(404,))
    if created is None:
        raise AscError(f"申请 Distribution 证书失败（已重试 5 次）：{last_error}")

    cert_b64 = (created.get("attributes") or {}).get("certificateContent")
    if not cert_b64:
        raise AscError(f"证书响应里没有 certificateContent：{json.dumps(created)[:800]}")
    cert = x509.load_der_x509_certificate(base64.b64decode(cert_b64))
    cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode("ascii")

    os.makedirs(args.out_dir, exist_ok=True)
    key_path = os.path.join(args.out_dir, "dist.key.pem")
    cert_path = os.path.join(args.out_dir, "dist.cert.pem")
    with open(key_path, "w", encoding="utf-8") as fh:
        fh.write(key_pem)
    with open(cert_path, "w", encoding="utf-8") as fh:
        fh.write(cert_pem)
    os.chmod(key_path, 0o600)
    print(f"      证书 subject={cert.subject.rfc4514_string()}")
    print(f"      证书到期={cert.not_valid_after_utc.date()} -> {cert_path}")

    # 4) 描述文件：先清掉本仓库历史上建的同名前缀 profile，再新建
    prefix = args.profile_prefix
    stale = [p for p in list_all("/v1/profiles", token, {"filter[profileType]": "IOS_APP_STORE"})
             if ((p.get("attributes") or {}).get("name") or "").startswith(prefix)]
    for p in stale:
        print(f"      清理旧描述文件 id={p['id']} name={(p.get('attributes') or {}).get('name')!r}")
        api("DELETE", f"/v1/profiles/{p['id']}", token, tolerate=(404,))

    run_tag = os.environ.get("GITHUB_RUN_NUMBER") or str(int(time.time()))
    profile_name = f"{prefix}{run_tag}"
    payload = {
        "data": {
            "type": "profiles",
            "attributes": {"name": profile_name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bid_id}},
                "certificates": {"data": [{"type": "certificates", "id": created["id"]}]},
            },
        }
    }
    profile = unwrap(api("POST", "/v1/profiles", token, payload=payload))
    pa = profile.get("attributes") or {}
    uuid = pa.get("uuid")
    content = pa.get("profileContent")
    if not uuid or not content:
        raise AscError(f"描述文件响应不完整：{json.dumps(profile)[:800]}")

    os.makedirs(PROFILE_DIR, exist_ok=True)
    profile_path = os.path.join(PROFILE_DIR, f"{uuid}.mobileprovision")
    with open(profile_path, "wb") as fh:
        fh.write(base64.b64decode(content))
    print(f"[4/4] 描述文件就绪：name={profile_name!r} uuid={uuid} "
          f"state={pa.get('profileState')} expires={pa.get('expirationDate')}")
    print(f"      已安装到 {profile_path}")

    pairs = {
        "SIGN_DIR": args.out_dir,
        "SIGN_KEY_PATH": key_path,
        "SIGN_CERT_PATH": cert_path,
        "PROFILE_PATH": profile_path,
        "PROFILE_UUID": uuid,
        "PROFILE_NAME": profile_name,
        "CERT_ID": created["id"],
        "CERT_SUBJECT": cert.subject.rfc4514_string(),
    }
    dump_signing_env(os.path.join(args.out_dir, "signing.env"), pairs)
    env_write(pairs)
    print(f"      环境变量已写入 {args.out_dir}/signing.env 与 $GITHUB_ENV")
    return 0


# ----------------------------------------------------------------- selfcheck

def cmd_selfcheck(args, token_unused=None) -> int:
    """不联网自检：确认 JWT 能签、CSR 能验、PEM 能读写。"""
    import jwt
    from cryptography import x509
    from cryptography.hazmat.primitives.asymmetric import ec

    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(
        serialization_encoding(), serialization_format(), serialization_none()
    ).decode("ascii")
    tmp = os.path.join(args.out_dir or ".", "_selfcheck.p8")
    os.makedirs(args.out_dir or ".", exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(pem)
    tok = make_token("SELFCHECK", "00000000-0000-0000-0000-000000000000", tmp)
    decoded = jwt.decode(tok, key.public_key(), algorithms=["ES256"],
                         audience="appstoreconnect-v1")
    assert decoded["aud"] == "appstoreconnect-v1"
    assert tok.count(".") == 2
    print(f"[ok] JWT HS/ES256 签名可被验签通过（len={len(tok)}）")

    key_pem, csr_pem, _ = _gen_key_and_csr("selfcheck")
    csr = x509.load_pem_x509_csr(csr_pem.encode("ascii"))
    assert csr.is_signature_valid, "CSR 自签名校验失败"
    print(f"[ok] CSR 自签名校验通过：{csr.subject.rfc4514_string()}")
    print(f"[ok] 私钥 PEM 长度 {len(key_pem)}")
    os.remove(tmp)
    print("selfcheck 全部通过")
    return 0


def serialization_encoding():
    from cryptography.hazmat.primitives import serialization
    return serialization.Encoding.PEM


def serialization_format():
    from cryptography.hazmat.primitives import serialization
    return serialization.PrivateFormat.PKCS8


def serialization_none():
    from cryptography.hazmat.primitives import serialization
    return serialization.NoEncryption()


# ----------------------------------------------------------------- main

def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="App Store Connect 手工签名工具")
    p.add_argument("--key-id", default=os.environ.get("APPSTORE_KEY_ID"))
    p.add_argument("--issuer-id", default=os.environ.get("APPSTORE_ISSUER_ID"))
    p.add_argument("--key-path", default=os.environ.get("APPSTORE_KEY_PATH"))
    p.add_argument("--bundle-id", default=os.environ.get("BUNDLE_ID", "com.realsuntime.solartime"))
    p.add_argument("--team-id", default=os.environ.get("APPLE_TEAM_ID"))
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("preflight", help="只读诊断")
    sp.add_argument("--json-out")

    ss = sub.add_parser("signing", help="申请证书与描述文件")
    ss.add_argument("--out-dir", required=True)
    ss.add_argument("--profile-prefix", default="TrueSolarTimeCI-")

    sc = sub.add_parser("selfcheck", help="本地自检（不联网）")
    sc.add_argument("--out-dir")

    args = p.parse_args(argv)

    if args.cmd == "selfcheck":
        return cmd_selfcheck(args)

    if not args.key_id or not args.issuer_id or not args.key_path:
        print("缺少 APPSTORE_KEY_ID / APPSTORE_ISSUER_ID / APPSTORE_KEY_PATH", file=sys.stderr)
        return 2
    if not os.path.exists(args.key_path):
        print(f"找不到 API 私钥：{args.key_path}", file=sys.stderr)
        return 2

    try:
        token = make_token(args.key_id, args.issuer_id, args.key_path)
    except Exception as exc:  # noqa: BLE001 - 想把原因完整打给 CI 日志
        print(f"生成 API Token 失败：{exc}", file=sys.stderr)
        return 3
    print(f"API Token 已生成（kid={args.key_id}, len={len(token)}）")

    try:
        if args.cmd == "preflight":
            return cmd_preflight(args, token)
        if args.cmd == "signing":
            return cmd_signing(args, token)
    except AscError as exc:
        print(f"\n::error::{exc}", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
