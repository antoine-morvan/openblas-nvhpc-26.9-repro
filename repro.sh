#!/usr/bin/env bash
set -e -u -o pipefail

##################################################################################
## Settings
##################################################################################

# NVHPC_VERSION=26.5 # successes
NVHPC_VERSION=26.9 # fails

REPRO_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
mkdir -p "${REPRO_SCRIPT_DIR}/downloads"

##################################################################################
## Compiler
##################################################################################

OPENMPI_EXTRA_CONFIGURE_FLAGS=()
case ${1:-nvhpc} in
    gcc)
        # use system gcc
        export CC=gcc
        export CXX=g++
        export FC=gfortran
        CC_VERSION=$(gcc -dumpfullversion -dumpversion)
        ;;
    nvhpc)
        (command -v module &> /dev/null) || { echo "error: missing 'module' command" ; exit 1 ; }
        # install nvhpc
        NVHPC_LONGVERSION=20${NVHPC_VERSION%.*}_${NVHPC_VERSION/./}
        CUDA_VERSION=multi

        NVHPC_DIR=nvhpc_${NVHPC_LONGVERSION}_Linux_$(uname -m)_cuda_${CUDA_VERSION}
        NVHPC_ARCHIVE=${NVHPC_DIR}.tar.gz
        NVHPC_URL=https://developer.download.nvidia.com/hpc-sdk/${NVHPC_VERSION}/${NVHPC_ARCHIVE}

        [ ! -f "${REPRO_SCRIPT_DIR}/downloads/${NVHPC_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/downloads/${NVHPC_ARCHIVE}" "${NVHPC_URL}"
        [ ! -d "${NVHPC_DIR}" ] && (echo "-- extract nvhpc" ; cd "${REPRO_SCRIPT_DIR}" ; tar xf "${REPRO_SCRIPT_DIR}/downloads/${NVHPC_ARCHIVE}")

        NVHPC_PREFIX_DIR="$(readlink -f "${REPRO_SCRIPT_DIR}/${NVHPC_DIR}.prefix")"
        NVHPC_REAL_PREFIX_DIR="${NVHPC_PREFIX_DIR}/$(uname -s)_$(uname -m)/${NVHPC_VERSION}"
        [ ! -x "${NVHPC_REAL_PREFIX_DIR}/compilers/bin/nvfortran" ] && (
            echo "-- install nvhpc"
            export NVHPC_SILENT=true
            export NVHPC_INSTALL_TYPE=auto
            export NVHPC_INSTALL_DIR="${NVHPC_PREFIX_DIR}"
            "${NVHPC_DIR}/install"
        )
        module use "${NVHPC_PREFIX_DIR}/modulefiles"
        module load nvhpc-nompi

        # module already sets these
        # export CC=nvcc
        # export CXX=nvc++
        # export FC=nvfortran

        CC_VERSION="${NVHPC_VERSION}"
        ;;
    *) echo "ERROR: unsupported compiler '$1'" ; exit 1 ;;
esac

set -x
$CC --version
$CXX --version
$FC --version
set +x


##################################################################################
## Open BLAS
##################################################################################

OPENBLAS_VERSION="0.3.34"
OPENBLAS_DIR=OpenBLAS-${OPENBLAS_VERSION}
OPENBLAS_ARCHIVE=${OPENBLAS_DIR}.tar.gz
OPENBLAS_URL=https://github.com/OpenMathLib/OpenBLAS/releases/download/v${OPENBLAS_VERSION}/${OPENBLAS_ARCHIVE}

[ ! -f "${REPRO_SCRIPT_DIR}/downloads/${OPENBLAS_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/downloads/${OPENBLAS_ARCHIVE}" "${OPENBLAS_URL}"
[ ! -d "${OPENBLAS_DIR}" ] && (echo "-- extract openblas" ; cd "${REPRO_SCRIPT_DIR}" && tar xf "${REPRO_SCRIPT_DIR}/downloads/${OPENBLAS_ARCHIVE}")

SOURCE_DIR="${REPRO_SCRIPT_DIR}/${OPENBLAS_DIR}"
BUILD_DIR="${REPRO_SCRIPT_DIR}/${OPENBLAS_DIR}.$(basename "${CC}")-${CC_VERSION}.build"
PREFIX_DIR="${REPRO_SCRIPT_DIR}/${OPENBLAS_DIR}.$(basename "${CC}")-${CC_VERSION}.prefix"

(
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    # OPENBLAS_THREADING_SPEC=("-DUSE_THREAD=ON" "-DUSE_OPENMP=ON")
    OPENBLAS_THREADING_SPEC=("-DUSE_THREAD=OFF" "-DUSE_OPENMP=OFF")

    OPENBLAS_ARCH_SPEC=("-DTARGET_CORE=SAPPHIRERAPIDS")

    if [ ! -f "${BUILD_DIR}/Makefile" ]; then
        cmake \
            -Wno-dev \
            -G 'Unix Makefiles' \
            -DCMAKE_INSTALL_LIBDIR="lib" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="${PREFIX_DIR}" \
            -DCMAKE_Fortran_FLAGS="${FCFLAGS:-}" \
            -DBUILD_SHARED_LIBS=ON \
            -DBUILD_STATIC_LIBS=ON \
            -DBUILD_BENCHMARKS=ON \
            -DBUILD_TESTING=OFF \
            -DNUM_THREADS="256" \
            -DDYNAMIC_ARCH=OFF \
            "${OPENBLAS_ARCH_SPEC[@]}" \
            "${OPENBLAS_THREADING_SPEC[@]}" \
            "${SOURCE_DIR}"
    fi

    set +e
    make -j $(nproc)
    RES=$?
    set -e
    if [ $RES != 0 ]; then
        make -j1 V=1 VERBOSE=1
        exit $RES
    fi
    make install
)

##################################################################################
## Exit
##################################################################################
exit 0
