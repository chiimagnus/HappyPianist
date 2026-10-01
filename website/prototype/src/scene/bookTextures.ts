import {
  CanvasTexture,
  LinearFilter,
  SRGBColorSpace,
} from 'three';
import type { PrototypeSong } from '../model/data.ts';
import type { FeedbackMode, PrototypeStage } from '../model/state.ts';

interface PageTextureInput {
  song: PrototypeSong;
  page: number;
  pageCount: number;
  measure: number;
  stage: PrototypeStage;
  session: boolean;
  feedback: FeedbackMode;
}

function canvasTexture(canvas: HTMLCanvasElement): CanvasTexture {
  const texture = new CanvasTexture(canvas);
  texture.colorSpace = SRGBColorSpace;
  texture.minFilter = LinearFilter;
  texture.magFilter = LinearFilter;
  texture.needsUpdate = true;
  return texture;
}

export function createCoverTexture(song: PrototypeSong, index: number): CanvasTexture {
  const canvas = document.createElement('canvas');
  canvas.width = 768;
  canvas.height = 1032;
  const context = canvas.getContext('2d');
  if (!context) throw new Error('2D canvas context unavailable');

  context.fillStyle = '#f4efdf';
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.strokeStyle = '#d9d1bd';
  context.lineWidth = 2;
  context.strokeRect(24, 24, 720, 984);

  context.textAlign = 'center';
  context.fillStyle = '#393f40';
  context.font = `${song.title.length > 16 ? 42 : 50}px Georgia, serif`;
  context.fillText(song.title, 384, 157, 640);
  context.font = '23px Georgia, serif';
  context.fillStyle = '#6d7064';
  context.fillText(song.composer, 384, 207);

  const gradient = context.createLinearGradient(0, 290, 0, 850);
  gradient.addColorStop(0, '#e1ddc9');
  gradient.addColorStop(1, song.tint);
  context.fillStyle = gradient;
  context.fillRect(70, 280, 628, 566);

  for (let layer = 0; layer < 10; layer += 1) {
    context.beginPath();
    context.moveTo(70, 846);
    for (let position = 70; position <= 698; position += 4) {
      const elevation = 555 + layer * 25
        + Math.sin(position * 0.01 + layer * 0.66 + index) * 40
        + Math.cos(position * 0.018 + layer) * 24;
      context.lineTo(position, elevation);
    }
    context.lineTo(698, 846);
    context.closePath();
    context.fillStyle = layer % 2 ? '#eff0df' : song.tint;
    context.globalAlpha = 0.18;
    context.fill();
  }

  context.globalAlpha = 0.8;
  context.fillStyle = '#f8ebc7';
  context.beginPath();
  context.arc(455 - index * 14, 423, 33, 0, Math.PI * 2);
  context.fill();
  context.globalAlpha = 1;

  context.font = '18px Georgia, serif';
  context.fillStyle = '#72776a';
  context.fillText('PIANO SOLO', 384, 916);
  context.font = '14px sans-serif';
  context.fillText('PROCEDURAL COVER · DESIGN SAMPLE', 384, 965);

  return canvasTexture(canvas);
}

export function createPageTexture({ song, page, pageCount, measure, stage, session, feedback }: PageTextureInput): CanvasTexture {
  const canvas = document.createElement('canvas');
  canvas.width = 768;
  canvas.height = 1032;
  const context = canvas.getContext('2d');
  if (!context) throw new Error('2D canvas context unavailable');

  context.fillStyle = '#f8f3e5';
  context.fillRect(0, 0, canvas.width, canvas.height);
  const gradient = context.createLinearGradient(0, 0, canvas.width, 0);
  gradient.addColorStop(0, '#d6cbb433');
  gradient.addColorStop(0.08, '#ffffff00');
  gradient.addColorStop(1, '#b1a48e12');
  context.fillStyle = gradient;
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.textAlign = 'center';

  if (page > pageCount) {
    context.fillStyle = '#747767';
    context.font = '26px Georgia, serif';
    context.fillText('End of score', 384, 500);
    context.font = '18px sans-serif';
    context.fillText('奇数末页 · 右侧为空白', 384, 546);
    return canvasTexture(canvas);
  }

  context.font = '34px Georgia, serif';
  context.fillStyle = '#343a39';
  context.fillText(song.title, 384, 77, 650);
  context.font = '16px sans-serif';
  context.fillStyle = '#788172';
  context.fillText('布局测试谱 · 并非该作品真实 MusicXML', 384, 113);

  for (let system = 0; system < 4; system += 1) {
    const top = 190 + system * 188;
    const firstMeasure = (page - 1) * 8 + system * 2 + 1;
    const active = session && measure >= firstMeasure && measure < firstMeasure + 2;
    const suggested = stage === 'result' && firstMeasure === 9 && feedback !== 'unknown';

    if (active || suggested) {
      context.fillStyle = feedback === 'unknown' ? '#8a969014' : '#d5bd7532';
      context.fillRect(105, top - 14, 577, 132);
      context.strokeStyle = feedback === 'unknown' ? '#909a90' : '#ba9c54';
      context.lineWidth = 2;
      context.strokeRect(105, top - 14, 577, 132);
    }

    context.strokeStyle = '#60655e';
    context.lineWidth = 1.3;
    for (let staffLine = 0; staffLine < 5; staffLine += 1) {
      const y = top + staffLine * 10;
      context.beginPath();
      context.moveTo(105, y);
      context.lineTo(682, y);
      context.stroke();
    }

    context.fillStyle = '#434944';
    context.font = '20px Georgia, serif';
    context.fillText('𝄞', 124, top + 35);
    for (let note = 0; note < 16; note += 1) {
      const x = 160 + note * 31;
      const y = top + 10 + ((note * 7 + page * 3 + system) % 5) * 10;
      context.beginPath();
      context.ellipse(x, y, 5.5, 4, -0.25, 0, Math.PI * 2);
      context.fill();
      context.beginPath();
      context.moveTo(x + 5, y);
      context.lineTo(x + 5, y - 28 - (note % 3) * 3);
      context.stroke();
    }

    for (let bar = 0; bar <= 2; bar += 1) {
      const barX = 105 + bar * 288.5;
      context.beginPath();
      context.moveTo(barX, top);
      context.lineTo(barX, top + 40);
      context.stroke();
    }

    if (active) {
      context.textAlign = 'left';
      context.font = '15px sans-serif';
      context.fillStyle = '#6b775e';
      context.fillText(feedback === 'unknown' ? '— 证据不足，不评价' : `› 当前小节 ${measure} · 模拟`, 105, top + 66);
      context.textAlign = 'center';
    }
  }

  context.font = '17px Georgia, serif';
  context.fillStyle = '#7b8072';
  context.fillText(String(page), 384, 987);
  return canvasTexture(canvas);
}
