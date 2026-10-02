import { useCallback, useEffect, useReducer, useRef } from 'react';
import {
  initialState as makeInitialState,
  transition,
  type PrototypeEvent,
  type PrototypeState,
  type Stage,
} from '../model.ts';

const cancelableKeyboardStages: readonly Stage[] = [
  'opening',
  'loading',
  'input',
  'permission',
  'midi',
  'a0',
  'c8',
  'ready',
  'discard-confirm',
];

interface PrototypeReviewBridge {
  snapshot: () => PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
}

declare global {
  interface Window {
    prototypeReview?: PrototypeReviewBridge;
  }
}

export function usePrototypeController(seed?: PrototypeState) {
  const [state, dispatch] = useReducer(transition, seed ?? makeInitialState());
  const stateRef = useRef(state);
  const delayedRef = useRef<number | undefined>(undefined);
  const tickerRef = useRef<number | undefined>(undefined);
  stateRef.current = state;

  const clearDelayed = useCallback(() => {
    if (delayedRef.current === undefined) return;
    window.clearTimeout(delayedRef.current);
    delayedRef.current = undefined;
  }, []);

  const clearTicker = useCallback(() => {
    if (tickerRef.current === undefined) return;
    window.clearInterval(tickerRef.current);
    tickerRef.current = undefined;
  }, []);

  const schedule = useCallback((nextState: PrototypeState) => {
    clearDelayed();

    let completionEvent: PrototypeEvent | undefined;
    let completionDelay = 750;
    if (nextState.stage === 'opening') completionEvent = { type: 'placed' };
    else if (nextState.stage === 'loading') completionEvent = { type: 'loaded' };
    else if (nextState.stage === 'handoff') {
      completionEvent = { type: 'arrived' };
      completionDelay = 1100;
    } else if (nextState.stage === 'saving') {
      completionEvent = nextState.progressSaved
        ? { type: 'facts-saved' }
        : { type: 'progress-saved' };
      completionDelay = 700;
    }

    if (completionEvent !== undefined) {
      delayedRef.current = window.setTimeout(() => {
        delayedRef.current = undefined;
        dispatch(completionEvent);
      }, completionDelay);
    }

    const advancing = nextState.stage === 'practice'
      && !nextState.paused
      && nextState.ready
      && !nextState.editing
      && !document.hidden;
    if (advancing && tickerRef.current === undefined) {
      tickerRef.current = window.setInterval(() => dispatch({ type: 'tick' }), 1600);
    } else if (!advancing) {
      clearTicker();
    }
  }, [clearDelayed, clearTicker]);

  useEffect(() => {
    schedule(state);
  }, [schedule, state]);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const target = event.target;
      if (
        (target instanceof Element && target.matches('input,select,textarea'))
        || event.altKey
        || event.metaKey
        || event.ctrlKey
      ) {
        return;
      }

      const currentState = stateRef.current;
      if (
        (event.key === 'ArrowLeft' || event.key === 'ArrowRight')
        && (currentState.stage === 'library' || currentState.stage === 'detail')
      ) {
        event.preventDefault();
        const amount = event.key === 'ArrowLeft' ? -1 : 1;
        dispatch(
          currentState.stage === 'library'
            ? { type: 'select', value: currentState.selected + amount }
            : { type: 'page', value: amount },
        );
      }

      if (
        event.key === 'Escape'
        && cancelableKeyboardStages.includes(currentState.stage)
      ) {
        dispatch({ type: 'cancel' });
      }
    };

    const handleVisibilityChange = () => {
      if (document.hidden) {
        clearDelayed();
        clearTicker();
        if (stateRef.current.session) dispatch({ type: 'suspend' });
        return;
      }
      schedule(stateRef.current);
    };

    document.addEventListener('keydown', handleKeyDown);
    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [clearDelayed, clearTicker, schedule]);

  useEffect(() => {
    window.prototypeReview = {
      snapshot: () => structuredClone(stateRef.current),
      dispatch,
    };
    return () => {
      delete window.prototypeReview;
    };
  }, []);

  useEffect(() => () => {
    clearDelayed();
    clearTicker();
  }, [clearDelayed, clearTicker]);

  return { state, dispatch } as const;
}
