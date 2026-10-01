import { useEffect, useReducer, useState } from 'react';
import {
  initialState,
  transition,
  type PrototypeEvent,
  type PrototypeState,
} from '../model/state.ts';

export interface PrototypeRuntime {
  state: PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
  reducedMotion: boolean;
}

function isEditableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return target.matches('input, select, textarea, [contenteditable="true"]');
}

export function usePrototypeRuntime(): PrototypeRuntime {
  const [state, dispatch] = useReducer(transition, undefined, initialState);
  const [documentVisible, setDocumentVisible] = useState(() => !document.hidden);
  const [reducedMotion, setReducedMotion] = useState(
    () => window.matchMedia('(prefers-reduced-motion: reduce)').matches,
  );

  useEffect(() => {
    const media = window.matchMedia('(prefers-reduced-motion: reduce)');
    const handleChange = () => setReducedMotion(media.matches);
    handleChange();
    media.addEventListener('change', handleChange);
    return () => media.removeEventListener('change', handleChange);
  }, []);

  useEffect(() => {
    const handleVisibility = () => {
      const visible = !document.hidden;
      setDocumentVisible(visible);
      if (!visible && state.session) dispatch({ type: 'suspend' });
    };

    document.addEventListener('visibilitychange', handleVisibility);
    return () => document.removeEventListener('visibilitychange', handleVisibility);
  }, [state.session]);

  useEffect(() => {
    if (!documentVisible) return;

    let completion: { delay: number; event: PrototypeEvent } | undefined;
    switch (state.stage) {
      case 'opening':
        completion = { delay: 750, event: { type: 'placed' } };
        break;
      case 'loading':
        completion = { delay: 750, event: { type: 'loaded' } };
        break;
      case 'handoff':
        completion = { delay: 1100, event: { type: 'arrived' } };
        break;
      case 'saving':
        completion = {
          delay: 700,
          event: state.progressSaved ? { type: 'facts-saved' } : { type: 'progress-saved' },
        };
        break;
    }

    if (!completion) return;
    const timer = window.setTimeout(() => dispatch(completion.event), completion.delay);
    return () => window.clearTimeout(timer);
  }, [documentVisible, state.progressSaved, state.stage]);

  useEffect(() => {
    const advancing =
      documentVisible
      && state.stage === 'practice'
      && !state.paused
      && state.ready
      && !state.editing;

    if (!advancing) return;
    const ticker = window.setInterval(() => dispatch({ type: 'tick' }), 1600);
    return () => window.clearInterval(ticker);
  }, [documentVisible, state.editing, state.paused, state.ready, state.stage]);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (isEditableTarget(event.target) || event.altKey || event.metaKey || event.ctrlKey) return;

      if ((event.key === 'ArrowLeft' || event.key === 'ArrowRight') && (state.stage === 'library' || state.stage === 'detail')) {
        event.preventDefault();
        const amount = event.key === 'ArrowLeft' ? -1 : 1;
        if (state.stage === 'library') dispatch({ type: 'select', value: state.selected + amount });
        else dispatch({ type: 'page', value: amount });
        return;
      }

      if (event.key === 'Escape' && ['opening', 'loading', 'input', 'permission', 'midi', 'a0', 'c8', 'ready', 'discard-confirm'].includes(state.stage)) {
        dispatch({ type: 'cancel' });
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [state.selected, state.stage]);

  return { state, dispatch, reducedMotion };
}
