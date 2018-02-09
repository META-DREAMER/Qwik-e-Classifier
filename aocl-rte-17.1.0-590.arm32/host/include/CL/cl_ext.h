/*******************************************************************************
 * Copyright (c) 2008-2010 The Khronos Group Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and/or associated documentation files (the
 * "Materials"), to deal in the Materials without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Materials, and to
 * permit persons to whom the Materials are furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Materials.
 *
 * THE MATERIALS ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * MATERIALS OR THE USE OR OTHER DEALINGS IN THE MATERIALS.
 ******************************************************************************/

/* $Revision: 11928 $ on $Date: 2010-07-13 09:04:56 -0700 (Tue, 13 Jul 2010) $ */

/* cl_ext.h contains OpenCL extensions which don't have external */
/* (OpenGL, D3D) dependencies.                                   */

#ifndef __CL_EXT_H
#define __CL_EXT_H

#ifdef __cplusplus
extern "C" {
#endif

#ifdef __APPLE__
	#include <OpenCL/cl.h>
    #include <AvailabilityMacros.h>
#else
	#include <CL/cl.h>
#endif
#include <CL/cl_ext_intelfpga.h>

/* cl_khr_fp64 extension - no extension #define since it has no functions  */
#define CL_DEVICE_DOUBLE_FP_CONFIG                  0x1032

/* cl_khr_fp16 extension - no extension #define since it has no functions  */
#define CL_DEVICE_HALF_FP_CONFIG                    0x1033

/* Memory object destruction
 *
 * Apple extension for use to manage externally allocated buffers used with cl_mem objects with CL_MEM_USE_HOST_PTR
 *
 * Registers a user callback function that will be called when the memory object is deleted and its resources 
 * freed. Each call to clSetMemObjectCallbackFn registers the specified user callback function on a callback 
 * stack associated with memobj. The registered user callback functions are called in the reverse order in 
 * which they were registered. The user callback functions are called and then the memory object is deleted 
 * and its resources freed. This provides a mechanism for the application (and libraries) using memobj to be 
 * notified when the memory referenced by host_ptr, specified when the memory object is created and used as 
 * the storage bits for the memory object, can be reused or freed.
 *
 * The application may not call CL api's with the cl_mem object passed to the pfn_notify.
 *
 * Please check for the "cl_APPLE_SetMemObjectDestructor" extension using clGetDeviceInfo(CL_DEVICE_EXTENSIONS)
 * before using.
 */
#define cl_APPLE_SetMemObjectDestructor 1
cl_int	CL_API_ENTRY clSetMemObjectDestructorAPPLE(  cl_mem /* memobj */, 
                                        void (* /*pfn_notify*/)( cl_mem /* memobj */, void* /*user_data*/), 
                                        void * /*user_data */ )             CL_EXT_SUFFIX__VERSION_1_0;  


/* Context Logging Functions
 *
 * The next three convenience functions are intended to be used as the pfn_notify parameter to clCreateContext().
 * Please check for the "cl_APPLE_ContextLoggingFunctions" extension using clGetDeviceInfo(CL_DEVICE_EXTENSIONS)
 * before using.
 *
 * clLogMessagesToSystemLog fowards on all log messages to the Apple System Logger 
 */
#define cl_APPLE_ContextLoggingFunctions 1
extern void CL_API_ENTRY clLogMessagesToSystemLogAPPLE(  const char * /* errstr */, 
                                            const void * /* private_info */, 
                                            size_t       /* cb */, 
                                            void *       /* user_data */ )  CL_EXT_SUFFIX__VERSION_1_0;

/* clLogMessagesToStdout sends all log messages to the file descriptor stdout */
extern void CL_API_ENTRY clLogMessagesToStdoutAPPLE(   const char * /* errstr */, 
                                          const void * /* private_info */, 
                                          size_t       /* cb */, 
                                          void *       /* user_data */ )    CL_EXT_SUFFIX__VERSION_1_0;

/* clLogMessagesToStderr sends all log messages to the file descriptor stderr */
extern void CL_API_ENTRY clLogMessagesToStderrAPPLE(   const char * /* errstr */, 
                                          const void * /* private_info */, 
                                          size_t       /* cb */, 
                                          void *       /* user_data */ )    CL_EXT_SUFFIX__VERSION_1_0;


/************************ 
* cl_khr_icd extension *                                                  
************************/
#define cl_khr_icd 1

/* cl_platform_info                                                        */
#define CL_PLATFORM_ICD_SUFFIX_KHR                  0x0920

/* Additional Error Codes                                                  */
#define CL_PLATFORM_NOT_FOUND_KHR                   -1001

extern CL_API_ENTRY cl_int CL_API_CALL
clIcdGetPlatformIDsKHR(cl_uint          /* num_entries */,
                       cl_platform_id * /* platforms */,
                       cl_uint *        /* num_platforms */);

typedef CL_API_ENTRY cl_int (CL_API_CALL *clIcdGetPlatformIDsKHR_fn)(
    cl_uint          /* num_entries */,
    cl_platform_id * /* platforms */,
    cl_uint *        /* num_platforms */);


/******************************************
* cl_nv_device_attribute_query extension *
******************************************/
/* cl_nv_device_attribute_query extension - no extension #define since it has no functions */
#define CL_DEVICE_COMPUTE_CAPABILITY_MAJOR_NV       0x4000
#define CL_DEVICE_COMPUTE_CAPABILITY_MINOR_NV       0x4001
#define CL_DEVICE_REGISTERS_PER_BLOCK_NV            0x4002
#define CL_DEVICE_WARP_SIZE_NV                      0x4003
#define CL_DEVICE_GPU_OVERLAP_NV                    0x4004
#define CL_DEVICE_KERNEL_EXEC_TIMEOUT_NV            0x4005
#define CL_DEVICE_INTEGRATED_MEMORY_NV              0x4006


/*********************************
* cl_amd_device_attribute_query *
*********************************/
#define CL_DEVICE_PROFILING_TIMER_OFFSET_AMD        0x4036


#ifdef CL_VERSION_1_1
   /***********************************
    * cl_ext_device_fission extension *
    ***********************************/
    #define cl_ext_device_fission   1
    
    extern CL_API_ENTRY cl_int CL_API_CALL
    clReleaseDeviceEXT( cl_device_id /*device*/ ) CL_EXT_SUFFIX__VERSION_1_1; 
    
    typedef CL_API_ENTRY cl_int 
    (CL_API_CALL *clReleaseDeviceEXT_fn)( cl_device_id /*device*/ ) CL_EXT_SUFFIX__VERSION_1_1;

    extern CL_API_ENTRY cl_int CL_API_CALL
    clRetainDeviceEXT( cl_device_id /*device*/ ) CL_EXT_SUFFIX__VERSION_1_1; 
    
    typedef CL_API_ENTRY cl_int 
    (CL_API_CALL *clRetainDeviceEXT_fn)( cl_device_id /*device*/ ) CL_EXT_SUFFIX__VERSION_1_1;

    typedef cl_ulong  cl_device_partition_property_ext;
    extern CL_API_ENTRY cl_int CL_API_CALL
    clCreateSubDevicesEXT(  cl_device_id /*in_device*/,
                            const cl_device_partition_property_ext * /* properties */,
                            cl_uint /*num_entries*/,
                            cl_device_id * /*out_devices*/,
                            cl_uint * /*num_devices*/ ) CL_EXT_SUFFIX__VERSION_1_1;

    typedef CL_API_ENTRY cl_int 
    ( CL_API_CALL * clCreateSubDevicesEXT_fn)(  cl_device_id /*in_device*/,
                                                const cl_device_partition_property_ext * /* properties */,
                                                cl_uint /*num_entries*/,
                                                cl_device_id * /*out_devices*/,
                                                cl_uint * /*num_devices*/ ) CL_EXT_SUFFIX__VERSION_1_1;

    /* cl_device_partition_property_ext */
    #define CL_DEVICE_PARTITION_EQUALLY_EXT             0x4050
    #define CL_DEVICE_PARTITION_BY_COUNTS_EXT           0x4051
    #define CL_DEVICE_PARTITION_BY_NAMES_EXT            0x4052
    #define CL_DEVICE_PARTITION_BY_AFFINITY_DOMAIN_EXT  0x4053
    
    /* clDeviceGetInfo selectors */
    #define CL_DEVICE_PARENT_DEVICE_EXT                 0x4054
    #define CL_DEVICE_PARTITION_TYPES_EXT               0x4055
    #define CL_DEVICE_AFFINITY_DOMAINS_EXT              0x4056
    #define CL_DEVICE_REFERENCE_COUNT_EXT               0x4057
    #define CL_DEVICE_PARTITION_STYLE_EXT               0x4058
    
    /* error codes */
    #define CL_DEVICE_PARTITION_FAILED_EXT              -1057
    #define CL_INVALID_PARTITION_COUNT_EXT              -1058
    #define CL_INVALID_PARTITION_NAME_EXT               -1059
    
    /* CL_AFFINITY_DOMAINs */
    #define CL_AFFINITY_DOMAIN_L1_CACHE_EXT             0x1
    #define CL_AFFINITY_DOMAIN_L2_CACHE_EXT             0x2
    #define CL_AFFINITY_DOMAIN_L3_CACHE_EXT             0x3
    #define CL_AFFINITY_DOMAIN_L4_CACHE_EXT             0x4
    #define CL_AFFINITY_DOMAIN_NUMA_EXT                 0x10
    #define CL_AFFINITY_DOMAIN_NEXT_FISSIONABLE_EXT     0x100
    
    /* cl_device_partition_property_ext list terminators */
    #define CL_PROPERTIES_LIST_END_EXT                  ((cl_device_partition_property_ext) 0)
    #define CL_PARTITION_BY_COUNTS_LIST_END_EXT         ((cl_device_partition_property_ext) 0)
    #define CL_PARTITION_BY_NAMES_LIST_END_EXT          ((cl_device_partition_property_ext) 0 - 1)



#endif /* CL_VERSION_1_1 */


/* Intel FPGA extensions. */


/*********************************
* cl_intelfpga_mem_banks
*********************************/
/* cl_mem_flags - bitfield */
#define CL_CHANNEL_AUTO_INTELFPGA           (0<<16)
#define CL_CHANNEL_1_INTELFPGA              (1<<16)
#define CL_CHANNEL_2_INTELFPGA              (2<<16)
#define CL_CHANNEL_3_INTELFPGA              (3<<16)
#define CL_CHANNEL_4_INTELFPGA              (4<<16)
#define CL_CHANNEL_5_INTELFPGA              (5<<16)
#define CL_CHANNEL_6_INTELFPGA              (6<<16)
#define CL_CHANNEL_7_INTELFPGA              (7<<16)

#define CL_MEM_HETEROGENEOUS_INTELFPGA      (1<<19)

/*********************************
* For Host Channels
*********************************/
#define CL_MEM_HOST_WRITE_ONLY                      (1 << 7)
#define CL_MEM_HOST_READ_ONLY                       (1 << 8)



/*********************************
* clGetDeviceInfo extension
*********************************/
#define cl_intelfpga_device_temperature
/* Enum query for clGetDeviceInfo to get the die temperature in Celsius as a cl_int.
 * If the device does not support the query then the result will be 0 */
#define CL_DEVICE_CORE_TEMPERATURE_INTELFPGA        0x40F3



/*********************************
* CL API object tracking.
*********************************/
#define cl_intelfpga_live_object_tracking

/* Call this to begin tracking CL API objects.  
 * Ideally, do this immediately after getting the platform ID.
 * This takes extra space and time.
 */
extern CL_API_ENTRY void CL_API_CALL
clTrackLiveObjectsIntelFPGA(cl_platform_id platform);

/* Call this to be informed of all the live CL API objects, with their
 * reference counts.
 * The type name argument to the callback will be the string form of the type name
 * e.g. "cl_event" for a cl_event.
 */
extern CL_API_ENTRY void CL_API_CALL
clReportLiveObjectsIntelFPGA(
      cl_platform_id platform,
      void (CL_CALLBACK * /*report_fn*/)(
         void* /* user_data */,
         void* /* obj_ptr */,
         const char* /* type_name */, 
         cl_uint /* refcount */ ),
      void* /* user_data*/ );

/* Call this to query the FPGA and collect dynamic profiling data
 * for a single kernel.
 *
 * The event passed to this call must be the event used
 * in the kernel clEnqueueNDRangeKernel call. If the kernel
 * completes execution before this function is invoked, 
 * this function will return an event error code.
 *
 * NOTE: 
 * Invoking this function while the kernel is running will
 * disable the profile counters for a given interval.
 * For example, on a PCIe-based system this was measured
 * to be approximately 100us.
 */
extern CL_API_ENTRY cl_int CL_API_CALL
clGetProfileInfoIntelFPGA(
      cl_event /* kernel event */
      );

/* Call this to query the FPGA and collect dynamic profiling data
 * for all the kernels on the device. 
 * A boolean can be used to gather all enqueued and/or all autorun 
 * kernels, assuming there are profiling counters
 * 
 * NOTE: 
 * Invoking this function while the kernel is running will
 * disable the profile counters for a given interval.
 * For example, on a PCIe-based system this was measured
 * to be approximately 100us.
 */
extern CL_API_ENTRY cl_int CL_API_CALL
clGetProfileDataDeviceIntelFPGA(
            cl_device_id device_id,
            cl_program program,
            cl_bool read_enqueue_kernels,
            cl_bool read_auto_enqueued,
            cl_bool clear_counters_after_readback,
            size_t param_value_size,
            void *param_value,
            size_t *param_value_size_ret,
            cl_int *errcode_ret );


extern CL_API_ENTRY cl_int CL_API_CALL
clReadPipeIntelFPGA( cl_mem pipe,
                 void *ptr
               );

extern CL_API_ENTRY cl_int CL_API_CALL
clWritePipeIntelFPGA( cl_mem pipe,
                  void *ptr
                );

extern CL_API_ENTRY void * CL_API_CALL
clMapHostPipeIntelFPGA( cl_mem pipe,
                    cl_map_flags map_flags,
                    size_t requested_size,
                    size_t * mapped_size,
                    cl_int * errcode_ret
                  );

extern CL_API_ENTRY cl_int CL_API_CALL
clUnmapHostPipeIntelFPGA( cl_mem pipe,
                      void * mapped_ptr,
                      size_t size_to_unmap,
                      size_t * unmapped_size
                    );

/*********************************
* Intel FPGA offline compiler modes, offline device emulation.
*********************************/
#define cl_intelfpga_compiler_mode

#define CL_CONTEXT_COMPILER_MODE_INTELFPGA 0x40F0

#define CL_CONTEXT_COMPILER_MODE_OFFLINE_INTELFPGA 0
#define CL_CONTEXT_COMPILER_MODE_OFFLINE_CREATE_EXE_LIBRARY_INTELFPGA 1
#define CL_CONTEXT_COMPILER_MODE_OFFLINE_USE_EXE_LIBRARY_INTELFPGA 2
#define CL_CONTEXT_COMPILER_MODE_PRELOADED_BINARY_ONLY_INTELFPGA 3

/* This property is used to specify the root directory of
 * the executable program library for compiler modes 
 * CL_CONTEXT_COMPILER_MODE_OFFLINE_CREATE_EXE_LIBRARY and
 * CL_CONTEXT_COMPILER_MODE_OFFLINE_USE_EXE_LIBRARY.
 * The value should be a pointer to a C-style character string naming
 * the directory.  It can be relative, but will be resolved to an absolute
 * directory at context creation time.
 */
#define CL_CONTEXT_PROGRAM_EXE_LIBRARY_ROOT_INTELFPGA 0x40F1

/* This property is used to emulate, as much as possible,
 * having a device that is actually not attached.
 * Kernels may be enqueued but their code will not be run, 
 * so data coming back from the device may be invalid.
 * The value should be a pointer to a C-style character string with the
 * short name for the device.
 */
#define CL_CONTEXT_OFFLINE_DEVICE_INTELFPGA 0x40F2

/* FCD Support for Board Specific Functions */

extern CL_API_ENTRY void* CL_API_CALL 
clGetBoardExtensionFunctionAddressIntelFPGA(const char * /* func_name */,
                                         cl_device_id    /* device */);

extern CL_API_ENTRY cl_program CL_API_CALL
clCreateProgramWithBinaryAndProgramDeviceIntelFPGA(cl_context                     /* context */,
                          cl_uint                        /* num_devices */,
                          const cl_device_id *           /* device_list */,
                          const size_t *                 /* lengths */,
                          const unsigned char **         /* binaries */,
                          cl_int *                       /* binary_status */,
                          cl_int *                       /* errcode_ret */) CL_API_SUFFIX__VERSION_1_0;

/* Our own extra APIs */

extern CL_API_ENTRY cl_int CL_API_CALL
clReconfigurePLLIntelFPGA(
         cl_device_id device,
         const char *pll_settings_str);

extern CL_API_ENTRY cl_int CL_API_CALL
clResetKernelsIntelFPGA(
         cl_context context,
         cl_uint num_devices,
         const cl_device_id *device_list);

#ifdef __cplusplus
}
#endif


#endif /* __CL_EXT_H */
