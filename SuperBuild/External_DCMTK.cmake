
set(proj DCMTK)

# Set dependency list
set(${proj}_DEPENDENCIES "zlib")

# Include dependent projects if any
ExternalProject_Include_Dependencies(${proj} PROJECT_VAR proj DEPENDS_VAR ${proj}_DEPENDENCIES)

if(Slicer_USE_SYSTEM_${proj})
  unset(DCMTK_DIR CACHE)
  find_package(DCMTK REQUIRED)
endif()

# Sanity checks
if(DEFINED DCMTK_DIR AND NOT EXISTS ${DCMTK_DIR})
  message(FATAL_ERROR "DCMTK_DIR variable is defined but corresponds to nonexistent directory")
endif()

if(NOT DEFINED DCMTK_DIR AND NOT Slicer_USE_SYSTEM_${proj})
  set(EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS)

  if(CTEST_USE_LAUNCHERS)
    set(EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS
      -DCMAKE_PROJECT_DCMTK_INCLUDE:FILEPATH=${CMAKE_ROOT}/Modules/CTestUseLaunchers.cmake
      )
  endif()


  if(APPLE)
    list(APPEND EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS
      -DCMAKE_BUILD_WITH_INSTALL_RPATH:BOOL=ON
      )
  endif()

  if(UNIX)
    list(APPEND EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS
      -DDCMTK_FORCE_FPIC_ON_UNIX:BOOL=ON
      -DDCMTK_WITH_WRAP:BOOL=OFF   # CTK does not build on Mac with this option turned ON due to library dependencies missing
      )
  endif()

  ExternalProject_SetIfNotDefined(
    Slicer_${proj}_GIT_REPOSITORY
    "${EP_GIT_PROTOCOL}://github.com/commontk/DCMTK.git"
    QUIET
    )

  ExternalProject_SetIfNotDefined(
    Slicer_${proj}_GIT_TAG
    # Based of the official DCMTK release DCMTK-3.6.6
    # * https://github.com/DCMTK/dcmtk/commit/6cb30bd7fb42190e0188afbd8cb961c62a6fb9c9
    # * https://github.com/DCMTK/dcmtk/releases/tag/DCMTK-3.6.6
    #
    # with these backported patches:
    # * Fixed extra padding created for some segmentations.
    #   https://github.com/DCMTK/dcmtk/commit/b665e2ec2d5ce435e28da6c938736dcfa84d0da6
    #
    # * Made file extensions explicit for CMake CMP0115
    #   https://github.com/DCMTK/dcmtk/commit/d090b6d7c65e52e01e436a2473dc8ba3f384efbb
    #
    "0f9bf4d9e9a778c11fdddafca691b451c2b621bc" # patched-DCMTK-3.6.6_20210115
    QUIET
    )

  set(EP_SOURCE_DIR ${CMAKE_BINARY_DIR}/${proj})
  set(EP_BINARY_DIR ${CMAKE_BINARY_DIR}/${proj}-build)

  ExternalProject_Add(${proj}
    ${${proj}_EP_ARGS}
    GIT_REPOSITORY "${Slicer_${proj}_GIT_REPOSITORY}"
    GIT_TAG "${Slicer_${proj}_GIT_TAG}"
    SOURCE_DIR ${EP_SOURCE_DIR}
    BINARY_DIR ${EP_BINARY_DIR}
    CMAKE_CACHE_ARGS
      -DCMAKE_CXX_COMPILER:FILEPATH=${CMAKE_CXX_COMPILER}
      -DCMAKE_CXX_FLAGS:STRING=${ep_common_cxx_flags}
      -DCMAKE_C_COMPILER:FILEPATH=${CMAKE_C_COMPILER}
      -DCMAKE_C_FLAGS:STRING=${ep_common_c_flags}
      -DCMAKE_CXX_STANDARD:STRING=${CMAKE_CXX_STANDARD}
      -DCMAKE_CXX_STANDARD_REQUIRED:BOOL=${CMAKE_CXX_STANDARD_REQUIRED}
      -DCMAKE_CXX_EXTENSIONS:BOOL=${CMAKE_CXX_EXTENSIONS}
      -DBUILD_SHARED_LIBS:BOOL=ON
      -DDCMTK_WITH_DOXYGEN:BOOL=ON
      -DDCMTK_WITH_ZLIB:BOOL=ON
      -DDCMTK_WITH_OPENSSL:BOOL=ON
      -DDCMTK_WITH_PNG:BOOL=ON
      -DDCMTK_WITH_TIFF:BOOL=ON
      -DDCMTK_WITH_XML:BOOL=ON
      -DDCMTK_WITH_ICONV:BOOL=ON
      -DDCMTK_WITH_SNDFILE:BOOL=ON
      -DDCMTK_OVERWRITE_WIN32_COMPILER_FLAGS:BOOL=ON
      -DDCMTK_ENABLE_BUILTIN_DICTIONARY:BOOL=ON
      -DDCMTK_ENABLE_PRIVATE_TAGS:BOOL=ON
      -DDCMTK_WITH_ICU:BOOL=ON
      ${EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS}
    INSTALL_COMMAND ""
    DEPENDS
      ${${proj}_DEPENDENCIES}
  )

  ExternalProject_GenerateProjectDescription_Step(${proj})

  set(DCMTK_DIR ${EP_BINARY_DIR})

  #-----------------------------------------------------------------------------
  # Launcher setting specific to build tree

  set(_lib_subdir lib)
  if(WIN32)
    set(_lib_subdir bin)
  endif()

  set(DCMTK_LIBRARIES  "")

  # Find all libraries, store debug and release separately
  foreach(lib
          dcmpstat
          dcmsr
          dcmsign
          dcmtls
          dcmqrdb
          dcmnet
          dcmjpeg
          dcmimage
          dcmimgle
          dcmdata
          oficonv
          i2d
          dcmxml
          dcmtkcharls
          cmr
          dcmdsig
          dcmwlm
          dcmrt
          dcmiod
          dcmfg
          dcmseg
          dcmtract
          dcmpmap
          dcmect
          oflog
          ofstd
          ijg12
          ijg16
          ijg8
  )

    # Find Release libraries
    find_library(DCMTK_${lib}_LIBRARY_RELEASE
            ${lib}
            PATHS
            ${DCMTK_DIR}/${lib}/libsrc
            ${DCMTK_DIR}/${lib}/libsrc/Release
            ${DCMTK_DIR}/${lib}/Release
            ${DCMTK_DIR}/lib
            ${DCMTK_DIR}/lib/Release
            ${DCMTK_DIR}/dcmjpeg/lib${lib}/Release
            NO_DEFAULT_PATH
    )

    # Find Debug libraries
    find_library(DCMTK_${lib}_LIBRARY_DEBUG
            ${lib}${DCMTK_CMAKE_DEBUG_POSTFIX}
            PATHS
            ${DCMTK_DIR}/${lib}/libsrc
            ${DCMTK_DIR}/${lib}/libsrc/Debug
            ${DCMTK_DIR}/${lib}/Debug
            ${DCMTK_DIR}/lib
            ${DCMTK_DIR}/lib/Debug
            ${DCMTK_DIR}/dcmjpeg/lib${lib}/Debug
            NO_DEFAULT_PATH
    )

    mark_as_advanced(DCMTK_${lib}_LIBRARY_RELEASE)
    mark_as_advanced(DCMTK_${lib}_LIBRARY_DEBUG)

    # Add libraries to variable according to build type
    if(DCMTK_${lib}_LIBRARY_RELEASE)
      list(APPEND DCMTK_LIBRARIES ${DCMTK_${lib}_LIBRARY_RELEASE})
    endif()

    if(DCMTK_${lib}_LIBRARY_DEBUG)
      list(APPEND DCMTK_LIBRARIES ${DCMTK_${lib}_LIBRARY_DEBUG})
    endif()

  endforeach()

  set(CMAKE_THREAD_LIBS_INIT)
  if(DCMTK_oflog_LIBRARY_RELEASE OR DCMTK_oflog_LIBRARY_DEBUG)
    # Hack - Not having a DCMTKConfig.cmake file to read the settings from, we will attempt to
    # find the library in all cases.
    # Ideally, pthread library should be discovered only if DCMTK_WITH_THREADS is enabled.
    set(CMAKE_THREAD_PREFER_PTHREAD TRUE)
    find_package(Threads)
  endif()

  if(CMAKE_THREAD_LIBS_INIT)
    list(APPEND DCMTK_LIBRARIES ${CMAKE_THREAD_LIBS_INIT})
  endif()

  if(WIN32)
      list(APPEND DCMTK_LIBRARIES netapi32 wsock32)
  endif()

  foreach(dir
          config
          dcmdata
          dcmimage
          dcmimgle
          dcmjpeg
          dcmjpls
          dcmnet
          dcmpstat
          dcmqrdb
          dcmsign
          dcmsr
          dcmtls
          oficonv
          i2d
          dcmxml
          dcmtkcharls
          cmr
          dcmdsig
          dcmwlm
          dcmrt
          dcmiod
          dcmfg
          dcmseg
          dcmtract
          dcmpmap
          dcmect
          ofstd
          oflog)

    if(EXTDCMTK_SOURCE_DIR)
      set(SOURCE_DIR_PATH
              ${EXTDCMTK_SOURCE_DIR}/${dir}/include/dcmtk/${dir})
    endif()
    find_path(DCMTK_${dir}_INCLUDE_DIR
            ${DCMTK_${dir}_TEST_HEADER}
            PATHS
            ${DCMTK_DIR}/${dir}/include
            ${DCMTK_DIR}/${dir}
            ${DCMTK_DIR}/include/dcmtk/${dir}
            ${DCMTK_DIR}/${dir}/include/dcmtk/${dir}
            ${DCMTK_DIR}/include/${dir}
            ${SOURCE_DIR_PATH}
    )
    mark_as_advanced(DCMTK_${dir}_INCLUDE_DIR)
    list(APPEND DCMTK_INCLUDE_DIR_NAMES DCMTK_${dir}_INCLUDE_DIR)

    if(DCMTK_${dir}_INCLUDE_DIR)
      # add the 'include' path so eg
      #include "dcmtk/dcmimgle/dcmimage.h"
      # works
      get_filename_component(_include ${DCMTK_${dir}_INCLUDE_DIR} PATH)
      get_filename_component(_include ${_include} PATH)
      list(APPEND
              DCMTK_INCLUDE_DIRS
              ${DCMTK_${dir}_INCLUDE_DIR}
              ${_include})
    endif()
  endforeach()

  list(APPEND DCMTK_INCLUDE_DIRS ${DCMTK_DIR}/include)

  set(${proj}_LIBRARY_PATHS_LAUNCHER_BUILD ${DCMTK_DIR}/${_lib_subdir}/<CMAKE_CFG_INTDIR>)
  mark_as_superbuild(
    VARS ${proj}_LIBRARY_PATHS_LAUNCHER_BUILD
    LABELS "LIBRARY_PATHS_LAUNCHER_BUILD" "PATHS_LAUNCHER_BUILD"
    )

else()
  ExternalProject_Add_Empty(${proj} DEPENDS ${${proj}_DEPENDENCIES})
endif()

mark_as_superbuild(
        VARS ${proj}_INCLUDE_DIRS:STRING
        LABELS "FIND_PACKAGE"
        ALL_PROJECTS
)

mark_as_superbuild(
        VARS ${proj}_LIBRARIES:STRING
        LABELS "FIND_PACKAGE"
        ALL_PROJECTS
)

mark_as_superbuild(
  VARS DCMTK_DIR:PATH
  LABELS "FIND_PACKAGE"
  ALL_PROJECTS
  )
