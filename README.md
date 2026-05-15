# Advanced Gerstner Ocean Simulation

A high-performance, physics-driven 3D ocean simulation implemented in Godot 4. This project utilizes multi-iteration Gerstner wave algorithms for vertex displacement, an optimized two-pass treadmill chunk manager with distance-based Level of Detail (LOD) mesh swapping, and a custom advanced fragment shader featuring sub-surface scattering, dual-layer normal mapping and parameter-blended foam logic.

<img width="800" height="450" alt="Wave-Gif" src="https://github.com/user-attachments/assets/c702d674-3d55-470e-81cf-144ec2c52fa4" />

## 🛠️ Technical Specifications

### 1. Vertex Displacement & Dynamic Flattening
- **Gerstner Wave Functionality:** Real-time surface displacement is achieved through a multi-iteration loop calculating directional sine wave transformations. It dynamically computes continuous tangents and binormals per vertex to derive precise surface normals.

- **Horizon-Distance Flattening:** To eliminate visible mesh boundaries at extreme distances, the vertex shader evaluates distance vectors against camera matrices using a localized `smoothstep` distribution: $$\text{displacement} \times= (1.0 - \text{smoothstep}(\text{fade\_start}, \text{fade\_end}, \text{dist}))$$This flattens the simulation into a calm horizontal plane before the geometric grid perimeter is reached.

### 2. Optimized Chunk & LOD Management (OceanManager.gd)
The simulation employs a Node3D tool-script controller that maintains a localized $N \times N$ chunk grid centered on the active camera.
- **Two-Pass Treadmill System:** Avoids runtime dictionary allocation and hash map invalidation stutters by separating spatial edge-detection from chunk dictionary mutation. Pending displacements are queued into a lookup array during a read-only pass before execution.

- **Mesh-LOD State Management:** Dynamically scales vertex complexity across three distinct tiers (`mesh_high`, `mesh_med`, `mesh_low`) using distance-threshold checks. Assignments are strictly guarded via current state checks to prevent redundant pipeline redraw flags in Godot’s RenderingServer:  
`if chunk.mesh != target_mesh: chunk.mesh = target_mesh`

### 3. Advanced Surface Rendering (Fragment Shader)
- **Parameter-Blended Foam Layering:** Eliminates alpha-channel ghosting and terraced opacity halos. Instead of blending pre-computed transparency masks, the system passes multiple noise layers through a mathematical Screen blend ($A + B - AB$) to preserve derivative continuity. It then interpolates the threshold and softness parameters directly using a peak mask before evaluating a single, unified `smoothstep` loop.

- **Sub-Surface Scattering (SSS):** Simulates light transmission through wave crests by generating a normalized height mask, driving artificial backlight injection at thin geometric points.

- **Material Decoupling:** Modulates physical properties depending on surface condition. Surface regions mixed with foam dynamically strip specular reflections, suppress normal map depths, and scale roughness constants to $0.8$ to represent a turbulent, matte aerated emulsion.
## 🚀 Setup and Installation

### Prerequisites
1. **Godot Engine 4.x** (Forward+ Rendering Desktop Back-end recommended).
2. **Git LFS** initialized on your local environment.

### Deployment Instructions
1. Clone the repository and pull binary data:
```
git clone https://github.com/UrHighnez/ocean-simulation.git
cd ocean-simulation
git lfs install
git lfs pull
```
2.  **Import into Godot:**
    *   Open the Godot Project Manager.
    *   Select **Import** and navigate to the `/project` folder inside the cloned directory.
    *   Select `project.godot` and choose **Edit**.

3.  **LOD Verification:**
    Ensure that your pre-subdivided geometry assets (`water_high.tres`, `water_med.tres`, `water_low.tres`) are located in `project/assets/models/` and are actively assigned inside the `OceanManager` node inspector slot configuration.

---

## ⚙️ Configuration Profile

The default baseline uniforms for balanced GPU/CPU bounds across medium-to-high configurations:

| Uniform Parameter | Suggested Value | Functional Context |
| :--- | :--- | :--- |
| `Chunk Size` | `50.0` | Spatial dimension per chunk unit. |
| `Grid Radius` | `7` | $15 \times 15$ total streaming chunks. |
| `fade_start` | `150.0` | Horizon wave dampening activation distance. |
| `fade_end` | `300.0` | Hard zero geometric clamp for vertex height. |
| `foam_max_render_distance` | `60.0` | Maximum perimeter distance for foam computation fragments. |
