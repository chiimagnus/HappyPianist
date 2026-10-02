import { useLayoutEffect, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import {
  pageCount,
  songs,
  totalMeasures,
  type PrototypeEvent,
  type PrototypeState,
} from '../model.ts';

interface ProductUIProps {
  state: PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
  reviewOnly: boolean;
  reviewElement: HTMLDivElement | null;
  operationsElement: HTMLDivElement;
}

interface ActionButtonProps {
  state: PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
  label: ReactNode;
  action: string;
  event: PrototypeEvent;
  value?: string | number;
  className?: string;
  disabled?: boolean;
}

function detailHelp(
  state: PrototypeState,
  action: string,
  value: string | number | undefined,
  disabled: boolean,
): string | undefined {
  if (state.stage !== 'detail') return undefined;
  const key = `${action}:${value === undefined ? 'undefined' : value}`;
  switch (key) {
    case 'page:-1': return disabled ? '已经是第一组书页' : '翻到上一组书页，不改变练习进度';
    case 'page:1': return disabled ? '已经是最后一组书页' : '翻到下一组书页，不改变练习进度';
    case 'start:begin': return '从第 1 小节开始；先确认钢琴输入与位置';
    case 'start:resume': return '从上次保存的第 9 小节开始；先确认输入与定位（模拟进度）';
    case 'start:focus': return '只练第 9–12 小节；这是示例范围，不是当前演奏评价';
    case 'return:library': return '合拢这本谱，返回空间曲库；不会退出 3D';
    case 'listen:undefined': return state.audition
      ? '停止模拟试听状态；本原型没有真实音频'
      : '查看模拟试听状态；本原型没有真实音频';
    default: return undefined;
  }
}

function ActionButton({
  state,
  dispatch,
  label,
  action,
  event,
  value,
  className,
  disabled = false,
}: ActionButtonProps) {
  const help = detailHelp(state, action, value, disabled);
  return (
    <button
      type="button"
      data-action={action}
      data-value={value}
      data-help={help}
      className={className}
      disabled={disabled}
      onClick={() => dispatch(event)}
    >
      {label}
    </button>
  );
}

function ActionRow({ children }: { children: ReactNode }) {
  return <div className="row">{children}</div>;
}

function stageText(state: PrototypeState): readonly [string, string, string] {
  const name = songs[state.selected].title;
  switch (state.stage) {
    case 'entry':
      return ['原二维曲库 · 示意', '仍从熟悉的曲库开始', '现有二维产品保留。只有你主动进入，才打开空间书册。'];
    case 'opening':
      return ['进入中', '正在摆放空间书册', '原窗口仍保留。只有空间成功挂载并摆放后才隐藏。'];
    case 'entry-error':
      return ['进入未完成', '原二维曲库仍可使用', '取消或失败不关闭原窗口，不自动开始练习。'];
    case 'library':
      return ['空间曲库', name, '先选择，再打开。试听独立；书册不会随着镜头转动。'];
    case 'empty':
      return ['空间曲库', '还没有曲谱', '返回原二维管理窗口导入，不用示例书掩盖空库。'];
    case 'library-error':
      return ['空间曲库', '曲库暂未读取成功', '可以重试，或返回原二维曲库。'];
    case 'loading':
      return ['曲目详情', '正在准备这一本谱', '当前书保留；可取消，不会沿用上一首曲谱。'];
    case 'detail-error':
      return ['曲目详情', '这一本谱未能打开', '保留曲目选择，可以重试或合拢。'];
    case 'detail':
      return ['双页详情', name, `第 ${state.spread * 2 + 1}–${Math.min(pageCount, state.spread * 2 + 2)} 页 / ${pageCount} 页 · 测试谱。历史：第 9 小节（模拟）。`];
    case 'input':
      return ['准备 1 / 输入', '你用哪种方式弹奏？', '同一本书暂存在旁边；本原型不会请求麦克风或蓝牙权限。'];
    case 'permission':
      return ['准备 2 / 音频', '允许使用钢琴音频', '正式 App 在这里请求系统权限。本原型只演练允许、拒绝与重试。'];
    case 'midi':
      return ['准备 2 / MIDI', '连接你的 MIDI 钢琴', '连接成功后再定位，连接失败不能提前开始。'];
    case 'a0':
      return ['准备 3 / 定位', '先确认左端 A0', '正式操作由真实端点定位完成；这里使用示意钢琴与模拟确认。'];
    case 'c8':
      return ['准备 4 / 定位', '再确认右端 C8', '端点距离与演奏者方向都合法，才进入 Ready。'];
    case 'ready':
      return ['准备完成 · 模拟', '钢琴位置已确认', '确认后，同一本谱将移到琴上。不生成第二台钢琴。'];
    case 'handoff':
      return ['连续转场', '同一本谱，来到琴上', '曲目与当前页保持。移动动画不决定真实音乐启动时机。'];
    case 'practice':
      return [
        '琴上练习 · 模拟',
        state.editing ? '调整谱位' : `${state.paused ? '已暂停' : '练习中'} · 第 ${state.measure} 小节`,
        state.editing
          ? '明确编辑态才移动谱。取消恢复原位置；完成后仍暂停。'
          : `范围 ${state.range[0]}–${state.range[1]} · ${state.feedback === 'unknown' ? '— 证据不足，不评价' : '› 单一当前小节提示（模拟）'}${state.recording ? ' · ● 录音中（模拟）' : ''}${state.metronome ? ' · 节拍开启（无音频）' : ''}${state.companion !== 'off' ? ` · ${state.companion === 'teaching' ? '一次示范' : state.yielding ? '陪弹退让' : '陪弹参与'}（动作占位）` : ''}`,
      ];
    case 'result':
      return [
        '同谱结果 · 模拟',
        '这一轮完成了',
        state.feedback === 'unknown'
          ? '暂无法判断，不生成问题归因或复测建议。结果尚未保存。'
          : '一个建议：第 9–12 小节，放慢速度完成一次。样本反馈，非真实评估；尚未保存。',
      ];
    case 'saving':
      return [
        '安全返回',
        '正在保存，书先不合拢',
        state.progressSaved
          ? '进度已保存（内存模拟），等待会话事实保存。'
          : '先保存小节进度，再完成会话事实保存。两项成功才离开。',
      ];
    case 'save-error':
      return ['保留现场', '保存未完成', '仍在原书与原会话，可以重试、留下或明确放弃未保存部分。'];
    case 'discard-confirm':
      return ['再次确认', '放弃尚未保存的部分？', '已保存进度不删除；只放弃本次仍未保存的增量。'];
    case 'relocalize':
      return ['暂停 · 定位恢复', '重新确认钢琴位置', '错位的手和 Guide 已隐藏。谱与会话保留；恢复后不自动播放。'];
    case 'suspended':
      return ['系统中断 · 模拟', '会话暂时停在这里', '播放、手部与录音已停止。恢复需重新定位；刷新网页不保留这些内存。'];
    case 'manager':
      return ['原二维管理 · 示意', '导入与删除仍用原功能', '已离开空间曲库；本原型不操作实际文件。完成后主动重新进入 3D。'];
    case 'settings':
      return ['辅助设置 · 示意', '设置仍服务于这一轮练习', '原会话暂停。这里不是新练习窗口，不创建第二个会话。'];
  }
}

function ProductActions({ state, dispatch }: Pick<ProductUIProps, 'state' | 'dispatch'>) {
  const button = (
    label: ReactNode,
    action: string,
    event: PrototypeEvent,
    options: { value?: string | number; className?: string; disabled?: boolean } = {},
  ) => (
    <ActionButton
      state={state}
      dispatch={dispatch}
      label={label}
      action={action}
      event={event}
      value={options.value}
      className={options.className}
      disabled={options.disabled}
    />
  );

  const cancel = button('取消，保留原书', 'cancel', { type: 'cancel' });

  switch (state.stage) {
    case 'entry':
    case 'entry-error':
      return (
        <>
          {button(state.stage === 'entry-error' ? '重试进入 3D' : '进入 3D', 'enter', { type: 'enter' }, { className: 'primary' })}
          {state.stage === 'entry-error' ? button('留在 2D', 'cancel', { type: 'cancel' }) : null}
        </>
      );
    case 'opening':
      return button('取消进入', 'cancel', { type: 'cancel' });
    case 'library':
      return (
        <>
          <ActionRow>
            {button('← 上一本', 'select', { type: 'select', value: state.selected - 1 }, { value: state.selected - 1, disabled: state.selected === 0 })}
            {button('打开曲谱', 'open', { type: 'open' }, { className: 'primary' })}
            {button('下一本 →', 'select', { type: 'select', value: state.selected + 1 }, { value: state.selected + 1, disabled: state.selected === songs.length - 1 })}
          </ActionRow>
          <ActionRow>
            {button(state.audition ? '停止试听（模拟）' : '试听（模拟）', 'listen', { type: 'listen' })}
            {button('导入 / 管理', 'manage', { type: 'manage' })}
            {button('返回 2D', 'return', { type: 'return', value: '2d' }, { value: '2d' })}
          </ActionRow>
          <div className="row">
            <label htmlFor="search">查找演示曲目</label>
            <input
              type="search"
              id="search"
              placeholder="输入曲名或作曲家"
              autoComplete="off"
              value={state.search}
              onChange={(event) => dispatch({ type: 'search', value: event.currentTarget.value })}
            />
          </div>
        </>
      );
    case 'empty':
    case 'library-error':
      return (
        <>
          {button('重试', 'retry-library', { type: 'retry-library' })}
          {button('去 2D 管理', 'manage', { type: 'manage' })}
          {button('返回 2D', 'return', { type: 'return', value: '2d' }, { value: '2d' })}
        </>
      );
    case 'loading':
      return cancel;
    case 'detail-error':
      return (
        <>
          {button('重试打开', 'open', { type: 'open' }, { className: 'primary' })}
          {button('合拢回曲库', 'cancel', { type: 'cancel' })}
        </>
      );
    case 'detail':
      return (
        <>
          {button('↙', 'page', { type: 'page', value: -1 }, { value: -1, className: 'page-corner previous', disabled: state.spread === 0 })}
          {button('↘', 'page', { type: 'page', value: 1 }, { value: 1, className: 'page-corner next', disabled: state.spread === 2 })}
          {button('从头练习', 'start', { type: 'start', value: 'begin' }, { value: 'begin', className: 'practice-bookmark' })}
          {button(<>上次停在第 9 小节 · 模拟<br /><span>继续上次进度 →</span></>, 'start', { type: 'start', value: 'resume' }, { value: 'resume', className: 'history-mark' })}
          {state.spread === 0 ? button(<>练习<br />9–12<span>模拟</span></>, 'start', { type: 'start', value: 'focus' }, { value: 'focus', className: 'range-mark' }) : null}
          {button('合拢', 'return', { type: 'return', value: 'library' }, { value: 'library', className: 'spine-close' })}
          {button(state.audition ? '停止试听' : '试听', 'listen', { type: 'listen' }, { className: 'title-listen' })}
        </>
      );
    case 'input':
      return (
        <>
          <ActionRow>
            {button('真实钢琴音频', 'input', { type: 'input', value: 'audio' }, { value: 'audio', className: 'primary' })}
            {button('Bluetooth MIDI', 'input', { type: 'input', value: 'midi' }, { value: 'midi' })}
          </ActionRow>
          <ActionRow>
            {button('验证已存定位（模拟）', 'restore', { type: 'restore' })}
            {cancel}
          </ActionRow>
        </>
      );
    case 'permission':
    case 'midi':
      return (
        <>
          {button(state.stage === 'permission' ? '模拟允许 / 重试' : '模拟连接 / 重试', 'connect', { type: 'connect' }, { className: 'primary' })}
          {cancel}
        </>
      );
    case 'a0':
    case 'c8':
      return (
        <>
          {button(`模拟确认 ${state.stage.toUpperCase()}`, 'calibrate', { type: 'calibrate' }, { className: 'primary' })}
          {button('重做定位', 'recalibrate', { type: 'recalibrate' })}
          {cancel}
        </>
      );
    case 'ready':
      return (
        <>
          {button('确认，移到琴上', 'confirm', { type: 'confirm' }, { className: 'primary' })}
          {button('重做定位', 'recalibrate', { type: 'recalibrate' })}
          {cancel}
        </>
      );
    case 'handoff':
      return <span className="kicker">同一书册连续移动中…</span>;
    case 'practice':
      if (state.editing) {
        return (
          <>
            <ActionRow>
              {button('←', 'move-x', { type: 'move', axis: 0, value: -0.02 }, { value: -0.02 })}
              {button('→', 'move-x', { type: 'move', axis: 0, value: 0.02 }, { value: 0.02 })}
              {button('↑', 'move-y', { type: 'move', axis: 1, value: 0.02 }, { value: 0.02 })}
              {button('↓', 'move-y', { type: 'move', axis: 1, value: -0.02 }, { value: -0.02 })}
              {button('近一点', 'move-z', { type: 'move', axis: 2, value: 0.02 }, { value: 0.02 })}
              {button('远一点', 'move-z', { type: 'move', axis: 2, value: -0.02 }, { value: -0.02 })}
            </ActionRow>
            <ActionRow>
              {button('完成调整', 'edit-done', { type: 'edit-done' }, { className: 'primary' })}
              {button('取消调整', 'edit-cancel', { type: 'edit-done', cancel: true })}
              {button('重置谱位', 'reset-position', { type: 'reset-position' })}
            </ActionRow>
          </>
        );
      }
      return (
        <>
          <ActionRow>
            {button(state.paused ? '继续练习' : '暂停', 'play', { type: 'play' }, { className: 'primary' })}
            {button(state.controls ? '收起控制' : '唤出控制', 'controls', { type: 'controls' })}
            {button('保存回库', 'return', { type: 'return', value: 'library' }, { value: 'library' })}
          </ActionRow>
          {state.controls ? (
            <>
              <ActionRow>
                {button(state.recording ? '停止录音（模拟）' : '录音（模拟）', 'record', { type: 'record' }, { disabled: state.companion !== 'off' })}
                {button(state.metronome ? '关闭节拍' : '节拍（模拟）', 'metronome', { type: 'metronome' })}
                {button('调整谱位', 'edit', { type: 'edit' })}
              </ActionRow>
              <ActionRow>
                {button('示范一次', 'companion', { type: 'companion', value: 'teaching' }, { value: 'teaching' })}
                {button(state.companion === 'duet' ? '停止陪弹' : '开启陪弹', 'companion', { type: 'companion', value: state.companion === 'duet' ? 'off' : 'duet' }, { value: state.companion === 'duet' ? 'off' : 'duet' })}
                {button(state.loop ? '取消循环范围' : '循环第 9–16 小节', 'loop', { type: 'loop' })}
              </ActionRow>
              <ActionRow>
                {button('辅助设置', 'settings', { type: 'settings' })}
                {button('本轮完成（模拟）', 'finish', { type: 'finish' })}
                {button('保存退出 3D', 'return', { type: 'return', value: '2d' }, { value: '2d' })}
              </ActionRow>
              <div className="row">
                <label htmlFor="seek">明确跳练小节 · {state.measure}</label>
                <input
                  id="seek"
                  type="range"
                  min={state.range[0]}
                  max={state.range[1]}
                  value={state.measure}
                  onChange={(event) => dispatch({ type: 'seek', value: Number(event.currentTarget.value) })}
                />
              </div>
            </>
          ) : null}
          {state.companion !== 'off' ? (
            <ActionRow>
              {button('停止伙伴动作', 'companion', { type: 'companion', value: 'off' }, { value: 'off' })}
              {state.companion === 'duet'
                ? button(state.yielding ? '恢复陪弹参与（模拟）' : '陪弹退让（模拟）', 'yield', { type: 'yield' })
                : null}
            </ActionRow>
          ) : null}
        </>
      );
    case 'result':
      return (
        <>
          <ActionRow>
            {button('重练建议范围', 'retest', { type: 'retest', value: 'focus' }, { value: 'focus', className: 'primary', disabled: state.feedback === 'unknown' })}
            {button('再练一遍', 'retest', { type: 'retest', value: 'all' }, { value: 'all' })}
            {button(state.measure < totalMeasures ? '继续后续小节' : '从头继续练习', 'continue', { type: 'continue' })}
          </ActionRow>
          <ActionRow>
            {button('保存回曲库', 'return', { type: 'return', value: 'library' }, { value: 'library' })}
            {button('保存退出 3D', 'return', { type: 'return', value: '2d' }, { value: '2d' })}
          </ActionRow>
        </>
      );
    case 'saving':
      return button('正在保存…', 'retry-save', { type: 'retry-save' }, { disabled: true });
    case 'save-error':
      return (
        <>
          {button('重试保存', 'retry-save', { type: 'retry-save' }, { className: 'primary' })}
          {button('留在原会话', 'stay', { type: 'stay' })}
          {button('放弃未保存部分…', 'discard', { type: 'discard' }, { className: 'danger' })}
        </>
      );
    case 'discard-confirm':
      return (
        <>
          {button('确认放弃并离开', 'discard-confirm', { type: 'discard-confirm' }, { className: 'danger' })}
          {button('取消，继续保留', 'cancel', { type: 'cancel' })}
        </>
      );
    case 'relocalize':
      return (
        <>
          {button('模拟重新定位 / 重试', 'relocalized', { type: 'relocalized' }, { className: 'primary' })}
          {state.session
            ? button('安全保存回库', 'return', { type: 'return', value: 'library' }, { value: 'library' })
            : cancel}
        </>
      );
    case 'suspended':
      return (
        <>
          {button('恢复并重新定位', 'resume', { type: 'resume' }, { className: 'primary' })}
          {button('安全保存回库', 'return', { type: 'return', value: 'library' }, { value: 'library' })}
        </>
      );
    case 'manager':
      return button('完成管理，返回原曲库', 'managed', { type: 'managed' }, { className: 'primary' });
    case 'settings':
      return (
        <>
          {button('返回同一练习', 'settings', { type: 'settings' }, { className: 'primary' })}
          {button('安全保存回库', 'return', { type: 'return', value: 'library' }, { value: 'library' })}
        </>
      );
  }
}

function Actions({ state, dispatch }: Pick<ProductUIProps, 'state' | 'dispatch'>) {
  const query = state.stage === 'library' ? state.search.trim().toLocaleLowerCase() : '';
  const matches = query
    ? songs.map((song, index) => ({ song, index })).filter(({ song }) => (
        `${song.title} ${song.composer}`.toLocaleLowerCase().includes(query)
      ))
    : [];

  return (
    <>
      <div id="actions"><ProductActions state={state} dispatch={dispatch} /></div>
      <div id="search-results">
        {query && matches.length === 0 ? '没有匹配的演示曲目。' : null}
        {matches.map(({ song, index }) => (
          <ActionButton
            key={`${song.title}:${index}`}
            state={state}
            dispatch={dispatch}
            label={song.title}
            action="select"
            value={index}
            event={{ type: 'select', value: index }}
          />
        ))}
      </div>
    </>
  );
}

function spatialStatus(state: PrototypeState): string {
  const status: Partial<Record<PrototypeState['stage'], string>> = {
    loading: '正在打开…', 'detail-error': '曲谱未能打开',
    empty: '还没有曲谱', 'library-error': '曲库读取失败', input: '选择钢琴输入（模拟）',
    permission: '允许钢琴音频（模拟）', midi: '连接 MIDI 钢琴（模拟）',
    ready: '准备完成（模拟）', handoff: '同一本谱，移到琴上',
    result: state.feedback === 'unknown' ? '证据不足，暂不评价' : '第 9–12 小节 · 放慢速度完成一次（模拟）',
    saving: state.progressSaved ? '正在完成会话保存…' : '正在保存进度…',
    'discard-confirm': '只放弃未保存部分；已保存内容保留',
    relocalize: '先重新确认钢琴位置', suspended: '已暂停，恢复后先重新定位', settings: '辅助设置（模拟）',
  };
  return [status[state.stage], state.message].filter(Boolean).join('\n');
}

export function ProductUI({ state, dispatch, reviewOnly, reviewElement, operationsElement }: ProductUIProps) {
  const [label, title, copy] = stageText(state);
  useLayoutEffect(() => {
    operationsElement.dataset.stage = state.stage;
  }, [operationsElement, state.stage]);
  const product = (
    <section id="product" className={reviewOnly ? 'review-only' : undefined}
      data-stage={state.stage} style={reviewOnly ? undefined : { left: '50%', top: 'max(150px, 34vh)' }}>
      <div className="kicker" id="stage-label">{label}</div>
      <h2 id="product-title">{title}</h2>
      <p id="product-copy">{copy}</p>
      <p id="message">{state.message}</p>
      {reviewOnly ? null : <Actions state={state} dispatch={dispatch} />}
    </section>
  );
  return (
    <>
      {reviewOnly && reviewElement ? createPortal(product, reviewElement) : product}
      {reviewOnly ? createPortal(
        <><div id="spatial-status">{spatialStatus(state)}</div><Actions state={state} dispatch={dispatch} /></>,
        operationsElement,
      ) : null}
    </>
  );
}
