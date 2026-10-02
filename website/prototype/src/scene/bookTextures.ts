import { CanvasTexture, SRGBColorSpace } from 'three';
import { pageCount, songs, type Song, type PrototypeState } from '../model.ts';

export const width = 0.32;
export const height = 0.43;

export interface PageSurface {
  canvas: HTMLCanvasElement;
  texture: CanvasTexture;
}

export function canvasTexture(canvas: HTMLCanvasElement, anisotropy: number) {
  const texture = new CanvasTexture(canvas);
  texture.colorSpace = SRGBColorSpace;
  texture.anisotropy = Math.min(anisotropy, 8);
  return texture;
}

export function coverTexture(song: Song, index: number, anisotropy: number) {
  const canvas = document.createElement('canvas');
  canvas.width = 768;
  canvas.height = 1032;
  const context = canvas.getContext('2d');
  if (context === null) throw new Error('Canvas 2D is unavailable');
  context.fillStyle = '#f4efdf';
  context.fillRect(0, 0, 768, 1032);
  context.strokeStyle = '#d9d1bd';
  context.lineWidth = 2;
  context.strokeRect(24, 24, 720, 984);
  context.fillStyle = '#393f40';
  context.textAlign = 'center';
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
      const elevation = 555 + layer * 25 + Math.sin(position * 0.01 + layer * 0.66 + index) * 40 + Math.cos(position * 0.018 + layer) * 24;
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
  return canvasTexture(canvas, anisotropy);
}

export function pageSurface(anisotropy: number): PageSurface {
  const canvas = document.createElement('canvas');
  canvas.width = 768;
  canvas.height = 1032;
  return { canvas, texture: canvasTexture(canvas, anisotropy) };
}

export function paintPage(surface: PageSurface, page: number, state: PrototypeState) {
  const context = surface.canvas.getContext('2d');
  if (context === null) throw new Error('Canvas 2D is unavailable');
  context.fillStyle = '#f8f3e5';
  context.fillRect(0, 0, 768, 1032);
  const gradient = context.createLinearGradient(0, 0, 768, 0);
  gradient.addColorStop(0, '#d6cbb433');
  gradient.addColorStop(0.08, '#ffffff00');
  gradient.addColorStop(1, '#b1a48e12');
  context.fillStyle = gradient;
  context.fillRect(0, 0, 768, 1032);
  context.textAlign = 'center';
  context.fillStyle = '#747767';
  if (page > pageCount) {
    context.font = '26px Georgia, serif';
    context.fillText('End of score', 384, 500);
    context.font = '18px sans-serif';
    context.fillText('奇数末页 · 右侧为空白', 384, 546);
    surface.texture.needsUpdate = true;
    return;
  }
  context.font = '34px Georgia, serif';
  context.fillStyle = '#343a39';
  context.fillText(songs[state.selected].title, 384, 77, 650);
  context.font = '16px sans-serif';
  context.fillStyle = '#788172';
  context.fillText('布局测试谱 · 并非该作品真实 MusicXML', 384, 113);
  context.textAlign = 'left';
  for (let system = 0; system < 4; system += 1) {
    const top = 190 + system * 188;
    const firstMeasure = (page - 1) * 8 + system * 2 + 1;
    const active = state.session && state.measure >= firstMeasure && state.measure < firstMeasure + 2;
    if (active || (state.stage === 'result' && firstMeasure === 9 && state.feedback !== 'unknown')) {
      context.fillStyle = state.feedback === 'unknown' ? '#8a969014' : '#d5bd7532';
      context.fillRect(105, top - 14, 577, 132);
      context.strokeStyle = state.feedback === 'unknown' ? '#909a90' : '#ba9c54';
      context.lineWidth = 2;
      context.strokeRect(105, top - 14, 577, 132);
    }
    context.fillStyle = '#5c635a';
    context.font = '18px Georgia, serif';
    context.fillText(String(firstMeasure), 65, top - 17);
    for (let staff = 0; staff < 2; staff += 1) {
      const staffTop = top + staff * 73;
      context.strokeStyle = '#555951';
      context.lineWidth = 1.15;
      for (let line = 0; line < 5; line += 1) {
        context.beginPath();
        context.moveTo(82, staffTop + line * 9);
        context.lineTo(690, staffTop + line * 9);
        context.stroke();
      }
      context.fillStyle = '#3e443f';
      context.font = '32px Georgia, serif';
      context.fillText(staff === 0 ? 'G' : 'F', 83, staffTop + 32);
      for (let note = 0; note < 10; note += 1) {
        const noteX = 135 + note * 52;
        const noteY = staffTop + 9 + ((note + firstMeasure + staff * 2) % 6) * 4.5;
        context.beginPath();
        context.ellipse(noteX, noteY, 8, 5.6, -0.35, 0, Math.PI * 2);
        context.fill();
        context.beginPath();
        context.moveTo(noteX + 7, noteY);
        context.lineTo(noteX + 7, noteY - 33);
        context.stroke();
        if (note % 2 === 0) {
          context.lineWidth = 4;
          context.beginPath();
          context.moveTo(noteX + 7, noteY - 33);
          context.lineTo(noteX + 59, noteY - 28);
          context.stroke();
          context.lineWidth = 1.15;
        }
      }
    }
    for (const barX of [82, 405, 690]) {
      context.beginPath();
      context.moveTo(barX, top);
      context.lineTo(barX, top + 109);
      context.stroke();
    }
    if (active) {
      context.font = '15px sans-serif';
      context.fillStyle = '#6b775e';
      context.fillText(state.feedback === 'unknown' ? '— 证据不足，不评价' : `› 当前小节 ${state.measure} · 模拟`, 105, top + 142);
    }
  }
  context.textAlign = 'center';
  context.font = '17px Georgia, serif';
  context.fillStyle = '#7b8072';
  context.fillText(String(page), 384, 987);
  surface.texture.needsUpdate = true;
}
