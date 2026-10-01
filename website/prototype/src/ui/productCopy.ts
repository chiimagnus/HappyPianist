import { pageCount, songs, totalMeasures } from '../model/data.ts';
import type { PrototypeState } from '../model/state.ts';

export interface ProductCopy {
  label: string;
  title: string;
  description: string;
}

export function productCopy(state: PrototypeState): ProductCopy {
  const song = songs[state.selected];
  const name = song?.title ?? '未知曲目';

  switch (state.stage) {
    case 'entry':
      return { label: '原二维曲库 · 示意', title: '仍从熟悉的曲库开始', description: '现有二维产品保留。只有你主动进入，才打开空间书册。' };
    case 'opening':
      return { label: '进入中', title: '正在摆放空间书册', description: '原窗口仍保留。只有空间成功挂载并摆放后才隐藏。' };
    case 'entry-error':
      return { label: '进入未完成', title: '原二维曲库仍可使用', description: '取消或失败不关闭原窗口，不自动开始练习。' };
    case 'library':
      return { label: '空间曲库', title: name, description: '先选择，再打开。试听独立；书册不会随着镜头转动。' };
    case 'empty':
      return { label: '空间曲库', title: '还没有曲谱', description: '返回原二维管理窗口导入，不用示例书掩盖空库。' };
    case 'library-error':
      return { label: '空间曲库', title: '曲库暂未读取成功', description: '可以重试，或返回原二维曲库。' };
    case 'loading':
      return { label: '曲目详情', title: '正在准备这一本谱', description: '当前书保留；可取消，不会沿用上一首曲谱。' };
    case 'detail-error':
      return { label: '曲目详情', title: '这一本谱未能打开', description: '保留曲目选择，可以重试或合拢。' };
    case 'detail':
      return {
        label: '双页详情',
        title: name,
        description: `第 ${state.spread * 2 + 1}–${Math.min(pageCount, state.spread * 2 + 2)} 页 / ${pageCount} 页 · 测试谱。历史：第 9 小节（模拟）。`,
      };
    case 'input':
      return { label: '准备 1 / 输入', title: '你用哪种方式弹奏？', description: '同一本书暂存在旁边；本原型不会请求麦克风或蓝牙权限。' };
    case 'permission':
      return { label: '准备 2 / 音频', title: '允许使用钢琴音频', description: '正式 App 在这里请求系统权限。本原型只演练允许、拒绝与重试。' };
    case 'midi':
      return { label: '准备 2 / MIDI', title: '连接你的 MIDI 钢琴', description: '连接成功后再定位，连接失败不能提前开始。' };
    case 'a0':
      return { label: '准备 3 / 定位', title: '先确认左端 A0', description: '正式操作由真实端点定位完成；这里使用示意钢琴与模拟确认。' };
    case 'c8':
      return { label: '准备 4 / 定位', title: '再确认右端 C8', description: '端点距离与演奏者方向都合法，才进入 Ready。' };
    case 'ready':
      return { label: '准备完成 · 模拟', title: '钢琴位置已确认', description: '确认后，同一本谱将移到琴上。不生成第二台钢琴。' };
    case 'handoff':
      return { label: '连续转场', title: '同一本谱，来到琴上', description: '曲目与当前页保持。移动动画不决定真实音乐启动时机。' };
    case 'practice':
      return {
        label: '琴上练习 · 模拟',
        title: state.editing ? '调整谱位' : `${state.paused ? '已暂停' : '练习中'} · 第 ${state.measure} 小节`,
        description: state.editing
          ? '明确编辑态才移动谱。取消恢复原位置；完成后仍暂停。'
          : `范围 ${state.range[0]}–${state.range[1]} · ${state.feedback === 'unknown' ? '— 证据不足，不评价' : '› 单一当前小节提示（模拟）'}${state.recording ? ' · ● 录音中（模拟）' : ''}${state.metronome ? ' · 节拍开启（无音频）' : ''}${state.companion !== 'off' ? ` · ${state.companion === 'teaching' ? '一次示范' : state.yielding ? '陪弹退让' : '陪弹参与'}（动作占位）` : ''}`,
      };
    case 'result':
      return {
        label: '同谱结果 · 模拟',
        title: '这一轮完成了',
        description: state.feedback === 'unknown'
          ? '暂无法判断，不生成问题归因或复测建议。结果尚未保存。'
          : '一个建议：第 9–12 小节，放慢速度完成一次。样本反馈，非真实评估；尚未保存。',
      };
    case 'saving':
      return {
        label: '安全返回',
        title: '正在保存，书先不合拢',
        description: state.progressSaved ? '进度已保存（内存模拟），等待会话事实保存。' : '先保存小节进度，再完成会话事实保存。两项成功才离开。',
      };
    case 'save-error':
      return { label: '保留现场', title: '保存未完成', description: '仍在原书与原会话，可以重试、留下或明确放弃未保存部分。' };
    case 'discard-confirm':
      return { label: '再次确认', title: '放弃尚未保存的部分？', description: '已保存进度不删除；只放弃本次仍未保存的增量。' };
    case 'relocalize':
      return { label: '暂停 · 定位恢复', title: '重新确认钢琴位置', description: '错位的手和 Guide 已隐藏。谱与会话保留；恢复后不自动播放。' };
    case 'suspended':
      return { label: '系统中断 · 模拟', title: '会话暂时停在这里', description: '播放、手部与录音已停止。恢复需重新定位；刷新网页不保留这些内存。' };
    case 'manager':
      return { label: '原二维管理 · 示意', title: '导入与删除仍用原功能', description: '已离开空间曲库；本原型不操作实际文件。完成后主动重新进入 3D。' };
    case 'settings':
      return { label: '辅助设置 · 示意', title: '设置仍服务于这一轮练习', description: '原会话暂停。这里不是新练习窗口，不创建第二个会话。' };
  }
}

export const lastMeasure = totalMeasures;
