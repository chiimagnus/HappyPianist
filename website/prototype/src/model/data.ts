export interface PrototypeSong {
  title: string;
  composer: string;
  tint: string;
}

export const songs: readonly PrototypeSong[] = [
  { title: 'Moonlight Sonata', composer: 'Ludwig van Beethoven', tint: '#72819a' },
  { title: 'Nocturne', composer: 'Frédéric Chopin', tint: '#687c83' },
  { title: 'Clair de Lune', composer: 'Claude Debussy', tint: '#9c9cab' },
  { title: 'Arabesque', composer: 'Claude Debussy', tint: '#8c9c80' },
  { title: 'Kinderszenen', composer: 'Robert Schumann', tint: '#b39378' },
  { title: 'Impromptu', composer: 'Franz Schubert', tint: '#8a8d9c' },
  { title: 'Gymnopédie', composer: 'Erik Satie', tint: '#97a8a4' },
];

export const pageCount = 5;
export const totalMeasures = 40;
