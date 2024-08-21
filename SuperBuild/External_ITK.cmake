
set(proj ITK)

# Set dependency list
set(${proj}_DEPENDENCIES "zlib" "VTK")
if(Slicer_BUILD_DICOM_SUPPORT)
  list(APPEND ${proj}_DEPENDENCIES DCMTK)
endif()
if(Slicer_USE_TBB)
  list(APPEND ${proj}_DEPENDENCIES tbb)
endif()

# Include dependent projects if any
ExternalProject_Include_Dependencies(${proj} PROJECT_VAR proj DEPENDS_VAR ${proj}_DEPENDENCIES)

if(Slicer_USE_SYSTEM_${proj})
  unset(ITK_DIR CACHE)
  find_package(ITK 5.1 REQUIRED NO_MODULE)
endif()

# Sanity checks
if(DEFINED ITK_DIR AND NOT EXISTS ${ITK_DIR})
  message(FATAL_ERROR "ITK_DIR variable is defined but corresponds to nonexistent directory")
endif()

if(NOT DEFINED ITK_DIR AND NOT Slicer_USE_SYSTEM_${proj})

  #-----------------------------------------------------------------------------
  # Launcher setting specific to build tree
  # Used below to both set the env. script and the launcher settings
  set(_lib_subdir lib)
  if(WIN32)
    set(_lib_subdir bin)
  endif()


  set(_paths)
  set(_links)

  # Variables used to update PATH, LD_LIBRARY_PATH or DYLD_LIBRARY_PATH in env. script below
  if(WIN32)
    set(_varname "PATH")
    set(_path_sep ";")
  elseif(UNIX)
    set(_path_sep ":")
    if(APPLE)
      set(_varname "DYLD_LIBRARY_PATH")
    else()
      set(_varname "LD_LIBRARY_PATH")
    endif()
  endif()

  ExternalProject_SetIfNotDefined(
    Slicer_${proj}_GIT_REPOSITORY
    "${EP_GIT_PROTOCOL}://github.com/Slicer/ITK"
    QUIET
    )

  ExternalProject_SetIfNotDefined(
    Slicer_${proj}_GIT_TAG
    "e18566d53a1b8a913cd460e70569e9b485137fba" # slicer-v5.4.0-2024-05-16-311b706
    QUIET
    )

  set(EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS)

  if(Slicer_USE_TBB)
    list(APPEND EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS
      -DModule_ITKTBB:BOOL=ON
      -DTBB_DIR:PATH=${TBB_DIR}
      )
  endif()

  if(Slicer_USE_PYTHONQT)
    # XXX Ensure python executable used for ITKModuleHeaderTest
    #     is the same as Slicer.
    #     This will keep the sanity check implemented in SlicerConfig.cmake
    #     quiet.
    list(APPEND EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS
      -DPYTHON_EXECUTABLE:PATH=${PYTHON_EXECUTABLE}
      )
    list(APPEND EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS
      # Required by FindPython3 CMake module used by VTK
      -DPython3_ROOT_DIR:PATH=${Python3_ROOT_DIR}
      -DPython3_INCLUDE_DIR:PATH=${Python3_INCLUDE_DIR}
      -DPython3_LIBRARY:FILEPATH=${Python3_LIBRARY}
      -DPython3_LIBRARY_DEBUG:FILEPATH=${Python3_LIBRARY_DEBUG}
      -DPython3_LIBRARY_RELEASE:FILEPATH=${Python3_LIBRARY_RELEASE}
      -DPython3_EXECUTABLE:FILEPATH=${Python3_EXECUTABLE}
      )
  endif()

  set(EP_SOURCE_DIR ${CMAKE_BINARY_DIR}/${proj})
  set(EP_BINARY_DIR ${CMAKE_BINARY_DIR}/${proj}-build)

  list(APPEND EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS
    -DITK_LEGACY_REMOVE:BOOL=OFF   #<-- Allow LEGACY ITKv4 features for now.
    -DITK_LEGACY_SILENT:BOOL=OFF   #<-- Use of legacy code will produce compiler warnings
    -DModule_ITKDeprecated:BOOL=ON #<-- Needed for ITKv5 now. (itkMultiThreader.h and MutexLock backwards compatibility.)
    )

  # DCMTK
  if(Slicer_BUILD_DICOM_SUPPORT)
    if(CMAKE_CONFIGURATION_TYPES)
      foreach(config ${CMAKE_CONFIGURATION_TYPES})
        list(APPEND _paths ${DCMTK_DIR}/${_lib_subdir}/${config})
        list(APPEND _links " -L${DCMTK_DIR}/${_lib_subdir}/${config} ")
      endforeach()
    else()
      list(APPEND _paths ${DCMTK_DIR}/${_lib_subdir})
      list(APPEND _links " -L${DCMTK_DIR}/${_lib_subdir} ")
    endif()

    list(APPEND EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS
            -DITK_USE_SYSTEM_DCMTK:BOOL=ON
            -DDCMTK_DIR:PATH=${DCMTK_DIR}
            -DDCMTK_LIBRARIES:PATH=${_links}
            -DITKIODCMTK_SYSTEM_LIBRARY_DIRS:STRING=${_paths}
            -DDICOM_SYSTEM_LIBRARY_DIRS:STRING=${_paths}
    )

  endif()

  list(APPEND EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS
          -DModule_ITKIODCMTK:BOOL=${Slicer_BUILD_DICOM_SUPPORT}
  )

  #Add additional user specified modules from this variable
  #Slicer_ITK_ADDITIONAL_MODULES
  #Add -DModule_${module} for each listed module
  #Names in list must match the expected module names in the ITK build system
  if(DEFINED Slicer_ITK_ADDITIONAL_MODULES)
    foreach(module ${Slicer_ITK_ADDITIONAL_MODULES})
      list(APPEND EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS
          -DModule_${module}:BOOL=ON
        )
    endforeach()
  endif()

  # environment
  set(_env_script ${CMAKE_BINARY_DIR}/${proj}_Env.cmake)
  include(ExternalProjectForNonCMakeProject)
  ExternalProject_Write_SetBuildEnv_Commands(${_env_script})

  file(APPEND ${_env_script}
"#------------------------------------------------------------------------------
# Added by '${CMAKE_CURRENT_LIST_FILE}'
set(ENV{${_varname}} \"${_paths}${_path_sep}\$ENV{${_varname}}\")

set(ENV{LDFLAGS} \"\$ENV{LDFLAGS} ${_links}\")


message(STATUS \"--------------------------------------------------\")
message(STATUS \"ENV = \$ENV{LDFLAGS} \")
message(STATUS \"ENV{${_varname}} = \$ENV{${_varname}} \")
message(STATUS \"--------------------------------------------------\")
")

  # build step
  set(_build_script ${CMAKE_BINARY_DIR}/${proj}_build_step.cmake)
  file(WRITE ${_build_script}
          "include(\"${_env_script}\")

  if(\"\${MAKE_COMMAND}\" STREQUAL \"\")
    message(FATAL_ERROR \"error: MAKE_COMMAND is not set !\")
  endif()

  execute_process(
    COMMAND \$\{MAKE_COMMAND\}
    WORKING_DIRECTORY \"${CMAKE_CURRENT_BINARY_DIR}/${proj}-build\"
  )
")

  set(CUSTOM_BUILD_COMMAND)
  if(CMAKE_GENERATOR MATCHES ".*Makefiles.*")
    # Use $(MAKE) as build command to propagate parallel make option
    set(CUSTOM_BUILD_COMMAND BUILD_COMMAND "$(MAKE)")
    set(make_command_definition -DMAKE_COMMAND=$(MAKE) )
  else()
    set(make_command_definition -DMAKE_COMMAND=${CMAKE_MAKE_PROGRAM})
  endif()

  set(CUSTOM_BUILD_COMMAND BUILD_COMMAND ${CMAKE_COMMAND}
    ${make_command_definition}
    -P ${_build_script})

  ExternalProject_Add(${proj}
    ${${proj}_EP_ARGS}
    GIT_REPOSITORY "${Slicer_${proj}_GIT_REPOSITORY}"
    GIT_TAG "${Slicer_${proj}_GIT_TAG}"
    SOURCE_DIR ${EP_SOURCE_DIR}
    BINARY_DIR ${EP_BINARY_DIR}
    ${CUSTOM_BUILD_COMMAND}
    CMAKE_CACHE_ARGS
      -DCMAKE_CXX_COMPILER:FILEPATH=${CMAKE_CXX_COMPILER}
      -DCMAKE_CXX_FLAGS:STRING=${ep_common_cxx_flags}
      -DCMAKE_C_COMPILER:FILEPATH=${CMAKE_C_COMPILER}
      -DCMAKE_C_FLAGS:STRING=${ep_common_c_flags}
      -DCMAKE_CXX_STANDARD:STRING=${CMAKE_CXX_STANDARD}
      -DCMAKE_CXX_STANDARD_REQUIRED:BOOL=${CMAKE_CXX_STANDARD_REQUIRED}
      -DCMAKE_CXX_EXTENSIONS:BOOL=${CMAKE_CXX_EXTENSIONS}
      -DITK_CXX_OPTIMIZATION_FLAGS:STRING= # Force compiler-default instruction set to ensure compatibility with older CPUs
      -DITK_C_OPTIMIZATION_FLAGS:STRING=  # Force compiler-default instruction set to ensure compatibility with older CPUs
      -DITK_INSTALL_ARCHIVE_DIR:PATH=${Slicer_INSTALL_LIB_DIR}
      -DITK_INSTALL_LIBRARY_DIR:PATH=${Slicer_INSTALL_LIB_DIR}
      -DBUILD_TESTING:BOOL=OFF
      -DBUILD_EXAMPLES:BOOL=OFF
      -DITK_BUILD_DEFAULT_MODULES:BOOL=ON
      -DGIT_EXECUTABLE:FILEPATH=${GIT_EXECUTABLE} # Used in ITKModuleRemote
      -DModule_ITKReview:BOOL=ON
      -DModule_MGHIO:BOOL=ON
      -DModule_ITKIOMINC:BOOL=ON
      -DModule_IOScanco:BOOL=ON
      -DModule_MorphologicalContourInterpolation:BOOL=ON
      -DModule_GrowCut:BOOL=ON
      -DModule_SimpleITKFilters:BOOL=${Slicer_USE_SimpleITK}
      -DModule_GenericLabelInterpolator:BOOL=ON
      -DModule_AdaptiveDenoising:BOOL=ON
      -DBUILD_SHARED_LIBS:BOOL=ON
      -DITK_INSTALL_NO_DEVELOPMENT:BOOL=ON
      -DKWSYS_USE_MD5:BOOL=ON # Required by SlicerExecutionModel
      -DITK_WRAPPING:BOOL=OFF #${BUILD_SHARED_LIBS} ## HACK:  QUICK CHANGE
      -DITK_WRAP_PYTHON:BOOL=OFF
      -DExternalData_OBJECT_STORES:PATH=${ExternalData_OBJECT_STORES}
      # VTK
      -DModule_ITKVtkGlue:BOOL=ON
      -DVTK_DIR:PATH=${VTK_DIR}
      # ZLIB
      -DITK_USE_SYSTEM_ZLIB:BOOL=ON
      -DZLIB_ROOT:PATH=${ZLIB_ROOT}
      -DZLIB_INCLUDE_DIR:PATH=${ZLIB_INCLUDE_DIR}
      -DZLIB_LIBRARY:FILEPATH=${ZLIB_LIBRARY}
      ${EXTERNAL_PROJECT_OPTIONAL_CMAKE_CACHE_ARGS}
    INSTALL_COMMAND ""
    DEPENDS
      ${${proj}_DEPENDENCIES}
    )

  ExternalProject_GenerateProjectDescription_Step(${proj})

  set(ITK_DIR ${EP_BINARY_DIR})

  if(NOT DEFINED ITK_VALGRIND_SUPPRESSIONS_FILE)
    set(ITK_VALGRIND_SUPPRESSIONS_FILE ${EP_SOURCE_DIR}/CMake/InsightValgrind.supp)
  endif()
  mark_as_superbuild(ITK_VALGRIND_SUPPRESSIONS_FILE:FILEPATH)

  # library paths
  set(${proj}_LIBRARY_PATHS_LAUNCHER_BUILD ${ITK_DIR}/${_lib_subdir}/<CMAKE_CFG_INTDIR>)
  mark_as_superbuild(
    VARS ${proj}_LIBRARY_PATHS_LAUNCHER_BUILD
    LABELS "LIBRARY_PATHS_LAUNCHER_BUILD"
    )

  #-----------------------------------------------------------------------------
  # Launcher setting specific to install tree

  # Since ITK Wrapping is installed in the Slicer standard site-packages
  # location, there is no need to specify custom setting for the install
  # case.

else()
  ExternalProject_Add_Empty(${proj} DEPENDS ${${proj}_DEPENDENCIES})
endif()

mark_as_superbuild(
  VARS ITK_DIR:PATH
  LABELS "FIND_PACKAGE"
  )
