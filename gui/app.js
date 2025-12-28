const canvasContainer = document.getElementById('canvas-container');
const canvas = document.getElementById('graph');
const overlayEl = document.getElementById('overlay');
const outputEl = document.getElementById('output');
const statusEl = document.getElementById('status');
const runBtn = document.getElementById('run-btn');

const nodes = [
  { id: 'news', label: 'News' },
  { id: 'parser', label: 'Parser' },
  { id: 'brain', label: 'Brain' },
  { id: 'watchdog', label: 'Watchdog' },
  { id: 'packet', label: 'Packet' },
];

let lastRun = null;
let selectedNodeId = null;
let hoveredNodeId = null;

function setOverlay(message) {
  if (!overlayEl) return;
  overlayEl.innerHTML = message;
  overlayEl.style.display = 'block';
}

function hideOverlay() {
  if (!overlayEl) return;
  overlayEl.innerHTML = '';
  overlayEl.style.display = 'none';
}

function layoutNodes(width, height) {
  const padding = 80;
  const usableWidth = width - padding * 2;
  const spacing = usableWidth / (nodes.length - 1);
  const y = height / 2;
  return nodes.map((node, idx) => ({
    ...node,
    x: padding + spacing * idx,
    y,
    r: 26,
  }));
}

function getCtx() {
  const ctx = canvas.getContext('2d');
  return ctx;
}

function drawGraph() {
  const rect = canvasContainer.getBoundingClientRect();
  const width = Math.max(200, Math.floor(rect.width || 800));
  const height = Math.max(200, Math.floor(rect.height || 600));
  canvas.width = width;
  canvas.height = height;
  const ctx = getCtx();
  if (!ctx) {
    setOverlay('Canvas not supported in this browser');
    return;
  }
  ctx.clearRect(0, 0, width, height);
  const nodePositions = layoutNodes(width, height);

  ctx.strokeStyle = '#2e7dff';
  ctx.lineWidth = 2;
  ctx.beginPath();
  for (let i = 0; i < nodePositions.length - 1; i++) {
    const a = nodePositions[i];
    const b = nodePositions[i + 1];
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
  }
  ctx.stroke();

  nodePositions.forEach((node) => {
    const isSelected = node.id === selectedNodeId;
    const isHovered = node.id === hoveredNodeId;
    ctx.beginPath();
    ctx.fillStyle = isSelected ? '#4caf50' : isHovered ? '#1f5dcc' : '#2196f3';
    ctx.strokeStyle = '#0b1021';
    ctx.lineWidth = isSelected ? 4 : 2;
    ctx.arc(node.x, node.y, node.r, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = '#e8ecf1';
    ctx.font = '14px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(node.label, node.x, node.y);
  });

  canvas.dataset.nodePositions = JSON.stringify(nodePositions);
}

function findNodeAt(x, y) {
  const positions = JSON.parse(canvas.dataset.nodePositions || '[]');
  return positions.find((node) => {
    const dx = x - node.x;
    const dy = y - node.y;
    return Math.sqrt(dx * dx + dy * dy) <= node.r;
  });
}

function showNodeOutput(nodeId) {
  if (!lastRun) {
    outputEl.textContent = 'No run yet.';
    return;
  }
  if (nodeId === 'packet' && lastRun.packet) {
    outputEl.textContent = JSON.stringify(lastRun.packet, null, 2);
    return;
  }
  const entry = lastRun.nodes.find((n) => n.id === nodeId);
  if (!entry) {
    outputEl.textContent = 'No data for node';
    return;
  }
  outputEl.textContent = JSON.stringify(entry.output, null, 2);
}

function handlePointer(event) {
  const rect = canvas.getBoundingClientRect();
  const x = event.clientX - rect.left;
  const y = event.clientY - rect.top;
  const hit = findNodeAt(x, y);
  hoveredNodeId = hit ? hit.id : null;
  if (event.type === 'pointerdown' && hit) {
    selectedNodeId = hit.id;
    showNodeOutput(selectedNodeId);
  }
  drawGraph();
}

async function runPipeline() {
  statusEl.textContent = 'Running...';
  try {
    const resp = await fetch('/pipeline/run', { method: 'POST' });
    const data = await resp.json();
    lastRun = data;
    selectedNodeId = 'packet';
    showNodeOutput('packet');
    statusEl.textContent = `Run ${data.run_id} complete`;
  } catch (err) {
    statusEl.textContent = 'Error running pipeline';
  }
}

function initCanvas() {
  hideOverlay();
  drawGraph();
  canvas.addEventListener('pointerdown', handlePointer);
  canvas.addEventListener('pointermove', handlePointer);
  window.addEventListener('resize', drawGraph);
}

runBtn.addEventListener('click', async () => {
  await runPipeline();
  drawGraph();
});

try {
  initCanvas();
} catch (err) {
  console.error(err);
  const msg = `Error initializing canvas: ${err.message || err}`;
  setOverlay(msg);
  statusEl.textContent = msg;
  outputEl.textContent = msg;
}
