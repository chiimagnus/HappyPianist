import type { ReactNode, Ref } from 'react';
import type { FaultCase, PrototypeState } from '../model.ts';
import { boards, faultCases, type BoardID } from '../reviewFixtures.ts';

interface ReviewPanelProps {
  state: PrototypeState;
  currentBoard: BoardID;
  onLoadBoard: (board: BoardID) => void;
  onInjectFault: (fault: FaultCase) => void;
  onReset: () => void;
  children?: ReactNode;
  explanationRef?: Ref<HTMLDivElement>;
}

export function ReviewPanel({
  state,
  currentBoard,
  onLoadBoard,
  onInjectFault,
  onReset,
  children,
  explanationRef,
}: ReviewPanelProps) {
  return (
    <details id="review">
      <summary>评审工具 · 全流程 / 异常 <span>非产品 UI</span></summary>
      <div className="review-body">
        <div id="review-explanation" ref={explanationRef}>
          <strong>当前流程说明 · 评审专用</strong>
          {children}
        </div>
        <div className="review-heading">
          <strong>十组设计板</strong>
          <small>跳转会重建演示状态；主流程请使用书旁按钮。</small>
        </div>
        <div id="board-buttons">
          {boards.map(([id, label]) => (
            <button
              key={id}
              type="button"
              data-board={id}
              className={id === currentBoard ? 'selected' : undefined}
              onClick={() => onLoadBoard(id)}
            >
              {id}<br />{label}
            </button>
          ))}
        </div>
        <div className="review-options">
          <label>
            故障演练
            <select
              id="fault-case"
              value=""
              onChange={(event) => {
                const value = event.currentTarget.value as FaultCase | '';
                if (value !== '') onInjectFault(value);
              }}
            >
              <option value="">选择一个可恢复的异常…</option>
              {faultCases.map((fault) => (
                <option key={fault.value} value={fault.value}>{fault.label}</option>
              ))}
            </select>
          </label>
          <button type="button" id="reset-demo" onClick={onReset}>重走完整流程</button>
        </div>
        <p id="review-state">
          演练状态：{state.stage} / 小节 {state.measure} / 未保存 {state.dirty ? '是' : '否'} / 进度 {state.progressSaved ? '成功' : '未完成'} / 会话 {state.factsSaved ? '成功' : '未完成'}。仅内存账本。
        </p>
        <a href="http://127.0.0.1:8765/.github/features/spatial-score-book-flow/design/boards/">打开静态设计板与分镜</a>
      </div>
    </details>
  );
}
