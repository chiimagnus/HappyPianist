export const CAMERA_TARGET = [0, 1.25, 0] as const;

export const CAMERA_VIEWS = {
  front: [0, 1.46, 1.75],
  oblique: [0.85, 1.58, 1.45],
  side: [1.55, 1.47, 0.56],
  top: [0.06, 2.45, 0.95],
} as const;

export type CameraView = keyof typeof CAMERA_VIEWS;
