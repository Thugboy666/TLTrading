const canvasContainer = document.getElementById('canvas-container');
const outputEl = document.getElementById('output');
const statusEl = document.getElementById('status');
const runBtn = document.getElementById('run-btn');

const nodes = [
  { id: 'news', label: 'NewsNode' },
  { id: 'parser', label: 'ParserNode' },
  { id: 'brain', label: 'BrainNode' },
  { id: 'watchdog', label: 'WatchdogNode' },
  { id: 'packet', label: 'PacketNode' },
];

let lastRun = null;

function initScene() {
  const width = canvasContainer.clientWidth;
  const height = canvasContainer.clientHeight;
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(70, width / height, 0.1, 1000);
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setSize(width, height);
  canvasContainer.appendChild(renderer.domElement);

  const geometry = new THREE.SphereGeometry(0.4, 32, 32);
  const materials = [
    new THREE.MeshBasicMaterial({ color: 0x4caf50 }),
    new THREE.MeshBasicMaterial({ color: 0x2196f3 }),
    new THREE.MeshBasicMaterial({ color: 0xff9800 }),
    new THREE.MeshBasicMaterial({ color: 0xf44336 }),
    new THREE.MeshBasicMaterial({ color: 0x9c27b0 }),
  ];

  const group = new THREE.Group();
  nodes.forEach((n, idx) => {
    const mesh = new THREE.Mesh(geometry, materials[idx % materials.length]);
    mesh.position.x = (idx - 2) * 2;
    mesh.userData = { id: n.id };
    group.add(mesh);
  });
  scene.add(group);

  camera.position.z = 6;

  const raycaster = new THREE.Raycaster();
  const mouse = new THREE.Vector2();
  function onClick(event) {
    const rect = renderer.domElement.getBoundingClientRect();
    mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(mouse, camera);
    const intersects = raycaster.intersectObjects(group.children);
    if (intersects.length > 0) {
      const nodeId = intersects[0].object.userData.id;
      showNodeOutput(nodeId);
    }
  }
  renderer.domElement.addEventListener('click', onClick);

  function animate() {
    requestAnimationFrame(animate);
    group.rotation.y += 0.002;
    renderer.render(scene, camera);
  }
  animate();
}

async function runPipeline() {
  statusEl.textContent = 'Running...';
  try {
    const resp = await fetch('/pipeline/run', { method: 'POST' });
    const data = await resp.json();
    lastRun = data;
    statusEl.textContent = `Run ${data.run_id} complete`;
  } catch (err) {
    statusEl.textContent = 'Error running pipeline';
  }
}

async function fetchRun(runId) {
  const resp = await fetch(`/pipeline/run/${runId}`);
  return resp.json();
}

function showNodeOutput(nodeId) {
  if (!lastRun) {
    outputEl.textContent = 'No run yet.';
    return;
  }
  const entry = lastRun.nodes.find(n => n.id === nodeId);
  if (!entry) {
    outputEl.textContent = 'No data for node';
    return;
  }
  outputEl.textContent = JSON.stringify(entry.output, null, 2);
}

runBtn.addEventListener('click', async () => {
  await runPipeline();
});

initScene();
