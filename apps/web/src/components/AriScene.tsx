import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { MeshoptDecoder } from "three/addons/libs/meshopt_decoder.module.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";

export default function AriScene({ motion = true }: { motion?: boolean }) {
  const host = useRef<HTMLDivElement>(null);
  const [ready, setReady] = useState(false);
  useEffect(() => {
    const node = host.current!;
    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({
        alpha: true,
        antialias: true,
        powerPreference: "low-power",
      });
    } catch {
      return;
    }
    let disposed = false,
      visible = true,
      frame = 0,
      last = 0;
    let object: THREE.Group | undefined,
      mixer: THREE.AnimationMixer | undefined;
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(32, 1, 0.1, 30);
    camera.position.set(0.3, 0.28, 5.1);
    camera.lookAt(0, 0.05, 0);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
    renderer.setClearColor(0x000000, 0);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.2;
    renderer.domElement.setAttribute("aria-hidden", "true");
    node.appendChild(renderer.domElement);
    const pmrem = new THREE.PMREMGenerator(renderer);
    const room = new RoomEnvironment();
    const environment = pmrem.fromScene(room, 0.04);
    scene.environment = environment.texture;
    room.dispose();
    pmrem.dispose();
    const key = new THREE.DirectionalLight(0xfff1dd, 3);
    key.position.set(2, 3, 4);
    scene.add(key);
    const rim = new THREE.DirectionalLight(0x71dbe3, 2);
    rim.position.set(-3, 1.5, -2);
    scene.add(rim);
    const pointer = { x: 0, y: 0 };
    const render = (time: number) => {
      if (disposed) return;
      if (visible && !document.hidden) {
        if (time - last > 1000 / 30) {
          const dt = Math.min((time - last) / 1000, 0.06);
          last = time;
          if (motion) {
            mixer?.update(dt);
            if (object) {
              object.rotation.y +=
                (pointer.x * 0.25 - object.rotation.y) * 0.07;
              object.rotation.x +=
                (pointer.y * 0.07 - object.rotation.x) * 0.07;
            }
          }
          renderer.render(scene, camera);
        }
      }
      if (motion) frame = requestAnimationFrame(render);
    };
    const loader = new GLTFLoader().setMeshoptDecoder(MeshoptDecoder);
    loader.load(
      "/mascot/ari_explorer.glb",
      (gltf) => {
        if (disposed) {
          disposeObject(gltf.scene);
          return;
        }
        object = gltf.scene;
        scene.add(object);
        mixer = new THREE.AnimationMixer(object);
        const clip = gltf.animations.find((a) => a.name === "idle_float");
        if (clip) mixer.clipAction(clip).play();
        mixer.update(0.25);
        renderer.render(scene, camera);
        setReady(true);
        frame = requestAnimationFrame(render);
      },
      undefined,
      () => setReady(false),
    );
    const resize = new ResizeObserver(() => {
      const { width, height } = node.getBoundingClientRect();
      renderer.setSize(width, height, false);
      camera.aspect = width / Math.max(height, 1);
      camera.updateProjectionMatrix();
      renderer.render(scene, camera);
    });
    resize.observe(node);
    const observer = new IntersectionObserver((entries) => {
      visible = entries[0].isIntersecting;
    });
    observer.observe(node);
    const onMove = (e: PointerEvent) => {
      const rect = node.getBoundingClientRect();
      pointer.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      pointer.y = ((e.clientY - rect.top) / rect.height) * 2 - 1;
    };
    const onLeave = () => {
      pointer.x = pointer.y = 0;
    };
    node.addEventListener("pointermove", onMove);
    node.addEventListener("pointerleave", onLeave);
    const lost = (e: Event) => {
      e.preventDefault();
      setReady(false);
    };
    renderer.domElement.addEventListener("webglcontextlost", lost);
    return () => {
      disposed = true;
      cancelAnimationFrame(frame);
      resize.disconnect();
      observer.disconnect();
      node.removeEventListener("pointermove", onMove);
      node.removeEventListener("pointerleave", onLeave);
      mixer?.stopAllAction();
      if (object) {
        mixer?.uncacheRoot(object);
        disposeObject(object);
      }
      environment.dispose();
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, [motion]);
  return (
    <div
      className="ari-scene"
      ref={host}
      role="img"
      aria-label="Ari, your animated 3D travel companion"
    >
      <img
        className={ready ? "ari-poster hidden" : "ari-poster"}
        src="/mascot/poster_idle.webp"
        alt=""
      />
      <span className="orbit orbit-one" />
      <span className="orbit orbit-two" />
    </div>
  );
}
function disposeObject(object: THREE.Object3D) {
  object.traverse((node) => {
    if (node instanceof THREE.Mesh) {
      node.geometry.dispose();
      const materials = Array.isArray(node.material)
        ? node.material
        : [node.material];
      materials.forEach((material) => {
        Object.values(material).forEach((value) => {
          if (value instanceof THREE.Texture) value.dispose();
        });
        material.dispose();
      });
    }
  });
}
