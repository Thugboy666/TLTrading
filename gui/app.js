const canvasContainer = document.getElementById('canvas-container');
const overlayEl = document.getElementById('overlay');
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

function initScene() {
  try {
    if (!window.THREE || !THREE.WebGLRenderer || !THREE.Scene || !THREE.PerspectiveCamera) {
      setOverlay('Three.js not loaded correctly (local vendor missing).');
      return;
    }

    const rect = canvasContainer.getBoundingClientRect();
    let width = Math.floor(rect.width);
    let height = Math.floor(rect.height);
    if (!width) width = 800;
    if (!height) height = 600;

    if (!THREE.Mesh || !THREE.SphereGeometry || !THREE.MeshBasicMaterial || !THREE.Group || !THREE.Raycaster || !THREE.Vector2) {
      setOverlay('Three.js not loaded correctly (local vendor missing).');
      return;
    }

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(70, width / height, 0.1, 1000);
    camera.position.z = 6;

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(window.devicePixelRatio || 1);
    renderer.setSize(width, height, false);
    canvasContainer.appendChild(renderer.domElement);

    if (typeof renderer.render !== 'function') {
      setOverlay('Three.js renderer is invalid or incomplete. WebGL not available.');
      return;
    }

    const gridHelper = new THREE.GridHelper(20, 20);
    scene.add(gridHelper);

    const originSphere = new THREE.Mesh(
      new THREE.SphereGeometry(0.5, 32, 32),
      new THREE.MeshBasicMaterial({ color: 0xffffff })
    );
    originSphere.position.set(0, 0, 0);
    scene.add(originSphere);

    const geometry = new THREE.SphereGeometry(0.5, 32, 32);
    const materials = [
      new THREE.MeshBasicMaterial({ color: 0x4caf50 }),
      new THREE.MeshBasicMaterial({ color: 0x2196f3 }),
      new THREE.MeshBasicMaterial({ color: 0xff9800 }),
      new THREE.MeshBasicMaterial({ color: 0xf44336 }),
      new THREE.MeshBasicMaterial({ color: 0x9c27b0 }),
    ];

    const group = new THREE.Group();
    const nodeMeshes = [];
    let selectedMesh = null;
    let selectedNodeId = null;
    nodes.forEach((n, idx) => {
      const mesh = new THREE.Mesh(geometry, materials[idx % materials.length].clone());
      mesh.position.x = (idx - 2) * 2;
      mesh.userData = { id: n.id };
      group.add(mesh);
      nodeMeshes.push(mesh);
    });
    scene.add(group);

    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2();

    const debugOverlay = document.createElement('div');
    debugOverlay.style.position = 'fixed';
    debugOverlay.style.top = '8px';
    debugOverlay.style.left = '8px';
    debugOverlay.style.padding = '4px 6px';
    debugOverlay.style.background = 'rgba(0,0,0,0.6)';
    debugOverlay.style.color = '#fff';
    debugOverlay.style.fontSize = '11px';
    debugOverlay.style.fontFamily = 'monospace';
    debugOverlay.style.borderRadius = '4px';
    debugOverlay.style.pointerEvents = 'none';
    debugOverlay.textContent = 'NDC: -, Intersects: 0, Hit: -';
    document.body.appendChild(debugOverlay);

    function updateSelection(mesh) {
      if (selectedMesh && selectedMesh.material) {
        selectedMesh.material.wireframe = false;
      }
      selectedMesh = mesh;
      if (selectedMesh && selectedMesh.material) {
        selectedMesh.material.wireframe = true;
      }
    }

    function onPointerDown(event) {
      const rect = renderer.domElement.getBoundingClientRect();
      mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
      raycaster.setFromCamera(mouse, camera);
      const intersects = raycaster.intersectObjects(nodeMeshes, false);
      let hitId = '-';
      if (intersects.length > 0) {
        const nodeId = intersects[0].object.userData.id;
        hitId = nodeId;
        selectedNodeId = nodeId;
        updateSelection(intersects[0].object);
        showNodeOutput(nodeId);
      }
      const ndcText = `NDC: ${mouse.x.toFixed(3)}, ${mouse.y.toFixed(3)}`;
      debugOverlay.textContent = `${ndcText} | Intersects: ${intersects.length} | Hit: ${hitId}`;
    }
    renderer.domElement.addEventListener('pointerdown', onPointerDown);

    function onResize() {
      let newWidth = Math.floor(canvasContainer.clientWidth);
      let newHeight = Math.floor(canvasContainer.clientHeight);
      if (!newWidth) newWidth = 800;
      if (!newHeight) newHeight = 600;
      camera.aspect = newWidth / newHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(newWidth, newHeight, false);
    }
    window.addEventListener('resize', onResize);

    function animate() {
      requestAnimationFrame(animate);
      group.rotation.y += 0.002;
      renderer.render(scene, camera);
    }
    animate();

    hideOverlay();
  } catch (err) {
    console.error(err);
    setOverlay(`Error initializing scene: ${err.message || err}`);
  }
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

try {
  initScene();
} catch (err) {
  console.error(err);
  setOverlay(`Error initializing scene: ${err.message || err}`);
}
