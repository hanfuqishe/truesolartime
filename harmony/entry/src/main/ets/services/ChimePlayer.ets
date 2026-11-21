/**
 * 应用在前台时播放报时音（与 Android 端同一段 3200 Hz 蜂鸣），
 * 素材放在 resources/rawfile 下，短促、可区分：
 *   chime500.wav —— 进入关键时间（500 ms）
 *   chime100.wav —— 时辰交接（100 ms）
 */

import { resourceManager } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class ChimePlayer {
  private static player: media.AVPlayer | null = null;

  static async play(context: common.UIAbilityContext, rawFileName: string): Promise<void> {
    try {
      await ChimePlayer.stop();
      const player: media.AVPlayer = await media.createAVPlayer();
      ChimePlayer.player = player;
      // **必须显式设成「并发」焦点**：不设时 AVPlayer 默认按「暂停其他应用」处理，
      // 我们这种几百毫秒的提示音会把后台音乐掐断，而且短音结束后音乐不会自动恢复
      // （华为应用市场审核的同类驳回意见正是这条）。SHARE_MODE 让提示音与后台音频并发，
      // 系统据此走「并发播放」策略，音乐不中断。
      try {
        player.audioInterruptMode = audio.InterruptMode.SHARE_MODE;
      } catch (error) {
        console.warn(`chime audioInterruptMode failed: ${(error as BusinessError).code}`);
      }
      player.on('stateChange', (state: media.AVPlayerState) => {
        if (state === 'initialized') {
          // 走「通知」音频通道，与安卓的 USAGE_NOTIFICATION_EVENT 对齐：
          // 静音/铃声音量为 0 时不响，跟着系统通知音量走，而不是媒体音量。
          try {
            const rendererInfo: audio.AudioRendererInfo = {
              usage: audio.StreamUsage.STREAM_USAGE_NOTIFICATION,
              rendererFlags: 0
            };
            player.audioRendererInfo = rendererInfo;
          } catch (error) {
            console.warn(`chime audioRendererInfo failed: ${(error as BusinessError).code}`);
          }
          player.prepare();
        } else if (state === 'prepared') {
          player.play();
        } else if (state === 'completed') {
          ChimePlayer.release();
        }
      });
      player.on('error', (error: BusinessError) => {
        console.warn(`chime player error: ${error.code} ${error.message}`);
        ChimePlayer.release();
      });
      const descriptor: resourceManager.RawFileDescriptor = await context.resourceManager.getRawFd(rawFileName);
      player.fdSrc = { fd: descriptor.fd, offset: descriptor.offset, length: descriptor.length };
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      console.warn(`chime failed: ${failure.code} ${failure.message}`);
    }
  }

  private static async release(): Promise<void> {
    const player: media.AVPlayer | null = ChimePlayer.player;
    ChimePlayer.player = null;
    if (player !== null) {
      try {
        await player.release();
      } catch (error) {
        // 已释放则忽略。
      }
    }
  }

  static async stop(): Promise<void> {
    await ChimePlayer.release();
  }
}
