# prodsim: a stand-in for the prod software

A small sensor pipeline that uses every package in `dist/` plus the RHEL
libraries the prod software links. It exercises the kide workflow end to
end: the kide container builds the dist libraries into `/workspace/ibn-dist`
and the project into `/workspace`, and the host runs the result from
`~/workspace`.

| Program | What it does | Uses |
|---|---|---|
| `prodsim-idlc` | own IDL compiler on TAO's front end (TAO's `drv_args.cpp`, `drv_preproc.cpp` and `tao_idl.cpp` copied from ACE+TAO 8.0.8, plus a JSON-schema backend); turns `idl/*.idl` into `share/prodsim/*.schema.json` at build time | `libTAO_IDL_FE`, `libACE`, TAO_IDL headers (`share/tao/TAO_IDL/include`), linked by plain names as prod does |
| `prodsim-control` | CORBA server for `ProdSim::TrackerControl` (threshold, running, stop); IOR in `prodsim-control.ior` | TAO ORB + POA, `tao_idl` skeletons |
| `prodsim-sensor` | reads a georeferenced GeoTIFF with GDAL (the dist's build: RHEL9's `gdal-libs` has no GTiff driver), scores 32x32 tiles with an ONNX model (`data/tile_sigmoid.onnx`, from `data/gen_model.py`), publishes `ProdSim::Detection` | GDAL (+ OSR), onnxruntime, OpenDDS publisher, CORBA client |
| `prodsim-tracker` | subscribes to `Detection`, publishes `ProdSim::Track`, writes `prodsim-report.json` | OpenDDS (RTPS, `GUID_t`), RapidJSON |
| `prodsim-viewer` | OpenGL 3.3 window: a pyramid that spins faster with more tracks and turns from blue to red with their confidence; `--frames N --screenshot F.ppm` for tests | GLFW, GLEW, OpenGL, OpenDDS subscriber |
| `prodsim-demo` | starts the pipeline from its install prefix | bash |

The prod build problems found on 2026-10-08/09 are covered: the TAO_IDL
headers in `share/tao/TAO_IDL/` (`prodsim-idlc`), ACE headers and libraries
for plain link names (`CPLUS_INCLUDE_PATH`, `LIBRARY_PATH`), and
`OpenDDS::DCPS::GUID_t` instead of the removed `RepoId` (`common.cpp`).

## Run

    test/prodsim/run.sh           # build in ibn-dev, run on prodsim-host under Xvfb, check
    test/prodsim/run.sh --show    # the same, but the viewer opens on your display

`run.sh` needs the ibn-dev image from this checkout
(`podman/Containerfile.ibn-dev`, with `build-dist.sh` in `/opt/ibn-dev/dist`;
`IBN_DEV_IMAGE=kide` uses kide built on top of it instead). The workspace is
`$PRODSIM_WORKSPACE` (default `~/.cache/prodsim-workspace`, not your
`~/workspace`); `build-dist.sh` runs only when `ibn-dist/` is not there yet
(~7 min the first time).

`prodsim-host` (`host/Containerfile`) stands in for the prod host: the same
base image and repos, only the runtime RPMs (gdal-libs, glfw, glew, Mesa,
Xvfb), no compiler and no dist libraries. The test fails if a prodsim binary
has an unresolved library, or if `prodsim-sensor` loads the host's GDAL
instead of the dist's (it writes and reads a GeoTIFF), i.e. if the `$ORIGIN` RPATH
(`$ORIGIN/../lib;$ORIGIN/../ibn-dist/lib;$ORIGIN/../ibn-dist/lib64`) does
not reach them.

By hand, inside kide (fish; in ibn-dev's bash: `. …/ibn-dist-env.sh` and
`-j "$(nproc)"`):

    build-dist.sh                          # once, into /workspace/ibn-dist
    source /workspace/ibn-dist/bin/ibn-dist-env.fish  # only in a shell opened before
    cmake -S <repo>/test/prodsim -B build -D CMAKE_INSTALL_PREFIX=/workspace
    cmake --build build -j (nproc)
    cmake --install build

and on the host:

    ~/workspace/bin/prodsim-demo           # window until you close it
