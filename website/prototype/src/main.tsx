import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '../style.css';
import { App } from './App';

const rootElement = document.querySelector<HTMLDivElement>('#app');

if (rootElement === null) {
  throw new Error('Missing #app root element');
}

createRoot(rootElement).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
