import type { ReactNode } from 'react';
import { pageCount, songs } from '../model/data.ts';
import type { PrototypeEvent, PrototypeState } from '../model/state.ts';
import { lastMeasure, productCopy } from './productCopy.ts';

interface ProductControlsProps {
  state: PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
}

interface ActionButtonProps {
  action: string;
  value?: string | number;
  className?: string;
  disabled?: boolean;
  help?: string;
  children: ReactNode;
  onClick: () => void;
  ariaLabel?: string;
}

function ActionButton({ action, value, className = '', disabled = false, help, children, onClick, ariaLabel }: ActionButtonProps) {
  return (
    <button
      type="button"
      data-action={action}
      data-value={value}
      data-help={help}
      className={className}
      disabled={disabled}
      onClick={onClick}
      aria-label={ariaLabel}
    >
      {children}
    </button>
  );
}

function Row({ children }: { children: ReactNode }) {
  return <div className="action-row">{children}</div>;
}

function detailHelp(state: PrototypeState, action: string, value?: string | number): string | undefined {
  const key = `${action}:${String(value)}`;
  const lastSpread = Math.ceil(pageCount / 2) - 1;
  const help: Record<string, string> = {
    'page:-1': state.spread === 0 ? '已经是第一组书页' : '翻到上一组书页，不改变练习进度',
    'page:1': state.spread === lastSpread ? '已经是最后一组书页' : '翻到下一组书页，不改变练习进度',
    'start:begin': '从第 1 小节开始；先确认钢琴输入与位置',
    'start:resume': '从上次保存的第 9 小节开始；先确认输入与定位（模拟进度）',
    'start:focus': '只练第 9–12 小节；这是示例范围，不是当前演奏评价',
    'return:library': '合拢这本谱，返回空间曲库；不会退出 3D',
    'listen:undefined': state.audition ? '停止模拟试听状态；本原型没有真实音频' : '查看模拟试听状态；本原型没有真实音频',
  };
  return help[key];
}

function DetailActions({ state, dispatch }: ProductControlsProps) {
  const lastSpread = Math.ceil(pageCount / 2) - 1;
  return (
    <div className="detail-actions">
      <ActionButton action="page" value={-1} className="page-corner previous" disabled={state.spread === 0} help={detailHelp(state, 'page', -1)} ariaLabel="上一组书页" onClick={() => dispatch({ type: 'page', value: -1 })}>↙</ActionButton>
      <ActionButton action="page" value={1} className="page-corner next" disabled={state.spread === lastSpread} help={detailHelp(state, 'page', 1)} ariaLabel="下一组书页" onClick={() => dispatch({ type: 'page', value: 1 })}>↘</ActionButton>
      <ActionButton action="start" value="begin" className="practice-bookmark" help={detailHelp(state, 'start', 'begin')} onClick={() => dispatch({ type: 'start', value: 'begin' })}>从头练习</ActionButton>
      <ActionButton action="start" value="resume" className="history-mark" help={detailHelp(state, 'start', 'resume')} onClick={() => dispatch({ type: 'start', value: 'resume' })}>上次停在第 9 小节 · 模拟 <span>继续上次进度 →</span></ActionButton>
      {state.spread === 0 && <ActionButton action="start" value="focus" className="range-mark" help={detailHelp(state, 'start', 'focus')} onClick={() => dispatch({ type: 'start', value: 'focus' })}>练习 9–12 <span>模拟</span></ActionButton>}
      <ActionButton action="return" value="library" className="spine-close" help={detailHelp(state, 'return', 'library')} onClick={() => dispatch({ type: 'return', value: 'library' })}>合拢</ActionButton>
      <ActionButton action="listen" className="title-listen" help={detailHelp(state, 'listen')} onClick={() => dispatch({ type: 'listen' })}>{state.audition ? '停止试听' : '试听'}</ActionButton>
    </div>
  );
}

function PracticeActions({ state, dispatch }: ProductControlsProps) {
  if (state.editing) {
    return (
      <>
        <Row>
          <ActionButton action="move-x" value={-0.02} ariaLabel="谱向左移动" onClick={() => dispatch({ type: 'move', axis: 0, value: -0.02 })}>←</ActionButton>
          <ActionButton action="move-x" value={0.02} ariaLabel="谱向右移动" onClick={() => dispatch({ type: 'move', axis: 0, value: 0.02 })}>→</ActionButton>
          <ActionButton action="move-y" value={0.02} ariaLabel="谱向上移动" onClick={() => dispatch({ type: 'move', axis: 1, value: 0.02 })}>↑</ActionButton>
          <ActionButton action="move-y" value={-0.02} ariaLabel="谱向下移动" onClick={() => dispatch({ type: 'move', axis: 1, value: -0.02 })}>↓</ActionButton>
          <ActionButton action="move-z" value={0.02} onClick={() => dispatch({ type: 'move', axis: 2, value: 0.02 })}>近一点</ActionButton>
          <ActionButton action="move-z" value={-0.02} onClick={() => dispatch({ type: 'move', axis: 2, value: -0.02 })}>远一点</ActionButton>
        </Row>
        <Row>
          <ActionButton action="edit-done" className="primary" onClick={() => dispatch({ type: 'edit-done' })}>完成调整</ActionButton>
          <ActionButton action="edit-cancel" onClick={() => dispatch({ type: 'edit-done', cancel: true })}>取消调整</ActionButton>
          <ActionButton action="reset-position" onClick={() => dispatch({ type: 'reset-position' })}>重置谱位</ActionButton>
        </Row>
      </>
    );
  }

  return (
    <>
      <Row>
        <ActionButton action="play" className="primary" onClick={() => dispatch({ type: 'play' })}>{state.paused ? '继续练习' : '暂停'}</ActionButton>
        <ActionButton action="controls" onClick={() => dispatch({ type: 'controls' })}>{state.controls ? '收起控制' : '唤出控制'}</ActionButton>
        <ActionButton action="return" value="library" onClick={() => dispatch({ type: 'return', value: 'library' })}>保存回库</ActionButton>
      </Row>
      {state.controls && (
        <>
          <Row>
            <ActionButton action="record" disabled={state.companion !== 'off'} onClick={() => dispatch({ type: 'record' })}>{state.recording ? '停止录音（模拟）' : '录音（模拟）'}</ActionButton>
            <ActionButton action="metronome" onClick={() => dispatch({ type: 'metronome' })}>{state.metronome ? '关闭节拍' : '节拍（模拟）'}</ActionButton>
            <ActionButton action="edit" onClick={() => dispatch({ type: 'edit' })}>调整谱位</ActionButton>
          </Row>
          <Row>
            <ActionButton action="companion" value="teaching" onClick={() => dispatch({ type: 'companion', value: 'teaching' })}>示范一次</ActionButton>
            <ActionButton action="companion" value={state.companion === 'duet' ? 'off' : 'duet'} onClick={() => dispatch({ type: 'companion', value: state.companion === 'duet' ? 'off' : 'duet' })}>{state.companion === 'duet' ? '停止陪弹' : '开启陪弹'}</ActionButton>
            <ActionButton action="loop" onClick={() => dispatch({ type: 'loop' })}>{state.loop ? '取消循环范围' : '循环第 9–16 小节'}</ActionButton>
          </Row>
          <Row>
            <ActionButton action="settings" onClick={() => dispatch({ type: 'settings' })}>辅助设置</ActionButton>
            <ActionButton action="finish" onClick={() => dispatch({ type: 'finish' })}>本轮完成（模拟）</ActionButton>
            <ActionButton action="return" value="2d" onClick={() => dispatch({ type: 'return', value: '2d' })}>保存退出 3D</ActionButton>
          </Row>
          <label className="range-control" htmlFor="seek">
            明确跳练小节 · {state.measure}
            <input
              id="seek"
              type="range"
              min={state.range[0]}
              max={state.range[1]}
              value={state.measure}
              aria-label="跳练小节"
              onChange={(event) => dispatch({ type: 'seek', value: Number(event.currentTarget.value) })}
            />
          </label>
        </>
      )}
      {state.companion !== 'off' && (
        <Row>
          <ActionButton action="companion" value="off" onClick={() => dispatch({ type: 'companion', value: 'off' })}>停止伙伴动作</ActionButton>
          {state.companion === 'duet' && <ActionButton action="yield" onClick={() => dispatch({ type: 'yield' })}>{state.yielding ? '恢复陪弹参与（模拟）' : '陪弹退让（模拟）'}</ActionButton>}
        </Row>
      )}
    </>
  );
}

function StageActions({ state, dispatch }: ProductControlsProps) {
  switch (state.stage) {
    case 'entry':
    case 'entry-error':
      return <><ActionButton action="enter" className="primary" onClick={() => dispatch({ type: 'enter' })}>{state.stage === 'entry-error' ? '重试进入 3D' : '进入 3D'}</ActionButton>{state.stage === 'entry-error' && <ActionButton action="cancel" onClick={() => dispatch({ type: 'cancel' })}>留在 2D</ActionButton>}</>;
    case 'opening':
      return <ActionButton action="cancel" onClick={() => dispatch({ type: 'cancel' })}>取消进入</ActionButton>;
    case 'library':
      return <>
        <Row>
          <ActionButton action="select" value={state.selected - 1} disabled={state.selected === 0} onClick={() => dispatch({ type: 'select', value: state.selected - 1 })}>← 上一本</ActionButton>
          <ActionButton action="open" className="primary" onClick={() => dispatch({ type: 'open' })}>打开曲谱</ActionButton>
          <ActionButton action="select" value={state.selected + 1} disabled={state.selected === songs.length - 1} onClick={() => dispatch({ type: 'select', value: state.selected + 1 })}>下一本 →</ActionButton>
        </Row>
        <Row>
          <ActionButton action="listen" onClick={() => dispatch({ type: 'listen' })}>{state.audition ? '停止试听（模拟）' : '试听（模拟）'}</ActionButton>
          <ActionButton action="manage" onClick={() => dispatch({ type: 'manage' })}>导入 / 管理</ActionButton>
          <ActionButton action="return" value="2d" onClick={() => dispatch({ type: 'return', value: '2d' })}>返回 2D</ActionButton>
        </Row>
      </>;
    case 'empty':
    case 'library-error':
      return <><ActionButton action="retry-library" onClick={() => dispatch({ type: 'retry-library' })}>重试</ActionButton><ActionButton action="manage" onClick={() => dispatch({ type: 'manage' })}>去 2D 管理</ActionButton><ActionButton action="return" value="2d" onClick={() => dispatch({ type: 'return', value: '2d' })}>返回 2D</ActionButton></>;
    case 'loading':
      return <ActionButton action="cancel" onClick={() => dispatch({ type: 'cancel' })}>取消，保留原书</ActionButton>;
    case 'detail-error':
      return <><ActionButton action="open" className="primary" onClick={() => dispatch({ type: 'open' })}>重试打开</ActionButton><ActionButton action="cancel" onClick={() => dispatch({ type: 'cancel' })}>合拢回曲库</ActionButton></>;
    case 'detail':
      return <DetailActions state={state} dispatch={dispatch} />;
    case 'input':
      return <><Row><ActionButton action="input" value="audio" className="primary" onClick={() => dispatch({ type: 'input', value: 'audio' })}>真实钢琴音频</ActionButton><ActionButton action="input" value="midi" onClick={() => dispatch({ type: 'input', value: 'midi' })}>Bluetooth MIDI</ActionButton></Row><Row><ActionButton action="restore" onClick={() => dispatch({ type: 'restore' })}>验证已存定位（模拟）</ActionButton><ActionButton action="cancel" onClick={() => dispatch({ type: 'cancel' })}>取消，保留原书</ActionButton></Row></>;
    case 'permission':
    case 'midi':
      return <><ActionButton action="connect" className="primary" onClick={() => dispatch({ type: 'connect' })}>{state.stage === 'permission' ? '模拟允许 / 重试' : '模拟连接 / 重试'}</ActionButton><ActionButton action="cancel" onClick={() => dispatch({ type: 'cancel' })}>取消，保留原书</ActionButton></>;
    case 'a0':
    case 'c8':
      return <><ActionButton action="calibrate" className="primary" onClick={() => dispatch({ type: 'calibrate' })}>模拟确认 {state.stage.toUpperCase()}</ActionButton><ActionButton action="recalibrate" onClick={() => dispatch({ type: 'recalibrate' })}>重做定位</ActionButton><ActionButton action="cancel" onClick={() => dispatch({ type: 'cancel' })}>取消，保留原书</ActionButton></>;
    case 'ready':
      return <><ActionButton action="confirm" className="primary" onClick={() => dispatch({ type: 'confirm' })}>确认，移到琴上</ActionButton><ActionButton action="recalibrate" onClick={() => dispatch({ type: 'recalibrate' })}>重做定位</ActionButton><ActionButton action="cancel" onClick={() => dispatch({ type: 'cancel' })}>取消，保留原书</ActionButton></>;
    case 'handoff':
      return <span className="kicker">同一书册连续移动中…</span>;
    case 'practice':
      return <PracticeActions state={state} dispatch={dispatch} />;
    case 'result':
      return <><Row><ActionButton action="retest" value="focus" className="primary" disabled={state.feedback === 'unknown'} onClick={() => dispatch({ type: 'retest', value: 'focus' })}>重练建议范围</ActionButton><ActionButton action="retest" value="all" onClick={() => dispatch({ type: 'retest', value: 'all' })}>再练一遍</ActionButton><ActionButton action="continue" onClick={() => dispatch({ type: 'continue' })}>{state.measure < lastMeasure ? '继续后续小节' : '从头继续练习'}</ActionButton></Row><Row><ActionButton action="return" value="library" onClick={() => dispatch({ type: 'return', value: 'library' })}>保存回曲库</ActionButton><ActionButton action="return" value="2d" onClick={() => dispatch({ type: 'return', value: '2d' })}>保存退出 3D</ActionButton></Row></>;
    case 'saving':
      return <ActionButton action="retry-save" disabled onClick={() => undefined}>正在保存…</ActionButton>;
    case 'save-error':
      return <><ActionButton action="retry-save" className="primary" onClick={() => dispatch({ type: 'retry-save' })}>重试保存</ActionButton><ActionButton action="stay" onClick={() => dispatch({ type: 'stay' })}>留在原会话</ActionButton><ActionButton action="discard" className="danger" onClick={() => dispatch({ type: 'discard' })}>放弃未保存部分…</ActionButton></>;
    case 'discard-confirm':
      return <><ActionButton action="discard-confirm" className="danger" onClick={() => dispatch({ type: 'discard-confirm' })}>确认放弃并离开</ActionButton><ActionButton action="cancel" onClick={() => dispatch({ type: 'cancel' })}>取消，继续保留</ActionButton></>;
    case 'relocalize':
      return <><ActionButton action="relocalized" className="primary" onClick={() => dispatch({ type: 'relocalized' })}>模拟重新定位 / 重试</ActionButton>{state.session ? <ActionButton action="return" value="library" onClick={() => dispatch({ type: 'return', value: 'library' })}>安全保存回库</ActionButton> : <ActionButton action="cancel" onClick={() => dispatch({ type: 'cancel' })}>取消，保留原书</ActionButton>}</>;
    case 'suspended':
      return <><ActionButton action="resume" className="primary" onClick={() => dispatch({ type: 'resume' })}>恢复并重新定位</ActionButton><ActionButton action="return" value="library" onClick={() => dispatch({ type: 'return', value: 'library' })}>安全保存回库</ActionButton></>;
    case 'manager':
      return <ActionButton action="managed" className="primary" onClick={() => dispatch({ type: 'managed' })}>完成管理，返回原曲库</ActionButton>;
    case 'settings':
      return <><ActionButton action="settings" className="primary" onClick={() => dispatch({ type: 'settings' })}>返回同一练习</ActionButton><ActionButton action="return" value="library" onClick={() => dispatch({ type: 'return', value: 'library' })}>安全保存回库</ActionButton></>;
  }
}

export function ProductControls({ state, dispatch }: ProductControlsProps) {
  const copy = productCopy(state);

  const query = state.search.trim().toLocaleLowerCase();
  const matches = query
    ? songs.map((song, index) => ({ song, index })).filter(({ song }) => `${song.title} ${song.composer}`.toLocaleLowerCase().includes(query))
    : [];

  return (
    <section className="product-panel" data-stage={state.stage} aria-labelledby="product-title">
      <div className="stage-label">{copy.label}</div>
      <h1 id="product-title">{copy.title}</h1>
      <p className="product-copy">{copy.description}</p>
      {state.message && <p className="product-message" role="alert">{state.message}</p>}
      <div className="product-actions"><StageActions state={state} dispatch={dispatch} /></div>
      {state.stage === 'library' && (
        <div className="search-area">
          <label htmlFor="search">查找演示曲目</label>
          <input
            id="search"
            type="search"
            placeholder="输入曲名或作曲家"
            autoComplete="off"
            value={state.search}
            onChange={(event) => dispatch({ type: 'search', value: event.currentTarget.value })}
          />
          {query && <div className="search-results">{matches.length ? matches.map(({ song, index }) => <ActionButton key={song.title} action="select" value={index} onClick={() => dispatch({ type: 'select', value: index })}>{song.title}</ActionButton>) : <span>没有匹配的演示曲目。</span>}</div>}
        </div>
      )}
      <div className="sr-only" role="status" aria-live="polite" aria-atomic="true">{copy.title}</div>
    </section>
  );
}
