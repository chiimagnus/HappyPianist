import {
  ACESFilmicToneMapping,
  SRGBColorSpace,
} from 'three';
import { WebGPURenderer } from 'three/webgpu';

interface RendererProps {
  canvas: EventTarget;
}

export async function createRenderer(props: RendererProps): Promise<WebGPURenderer> {
  const renderer = new WebGPURenderer({
    canvas: props.canvas as HTMLCanvasElement,
    antialias: true,
  });
  renderer.outputColorSpace = SRGBColorSpace;
  renderer.toneMapping = ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.12;
  renderer.shadowMap.enabled = true;
  await renderer.init();
  return renderer;
}
