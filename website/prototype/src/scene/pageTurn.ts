export interface PageTurnPages {
  direction: 1 | -1;
  left: number;
  right: number;
  leafFront: number;
  leafBack: number;
}

export function pageTurnPages(fromSpread: number, toSpread: number): PageTurnPages {
  const direction: 1 | -1 = toSpread > fromSpread ? 1 : -1;

  if (direction === 1) {
    return {
      direction,
      left: fromSpread * 2 + 1,
      right: toSpread * 2 + 2,
      leafFront: fromSpread * 2 + 2,
      leafBack: toSpread * 2 + 1,
    };
  }

  return {
    direction,
    left: toSpread * 2 + 1,
    right: fromSpread * 2 + 2,
    leafFront: toSpread * 2 + 2,
    leafBack: fromSpread * 2 + 1,
  };
}
