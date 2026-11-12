/**
 * 应用在前台时播放报时音（与 Android 端同一段 3200 Hz 蜂鸣），
 * 素材放在 resources/rawfile 下，短促、可区分：
 *   chime500.wav —— 进入关键时间（500 ms）
 *   chime250.wav —— 时辰交接（250 ms）
 */

import { resourceManager } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class ChimePlayer {
  private static player: media.AVPlayer | null = null;

  static async play(context: common.UIAbilityContext, rawFileName: string): Promise<void> {
    try {
      await ChimePlayer.stop();
      const player: media.AVPlayer = await media.createAVPlayer();
      ChimePlayer.player = player;
      player.on('stateChange', (state: media.AVPlayerState) => {
        if (state === 'initialized') {
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
