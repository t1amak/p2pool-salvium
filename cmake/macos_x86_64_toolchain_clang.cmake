set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_CROSSCOMPILING TRUE)

set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(CMAKE_C_COMPILER /usr/local/bin/x86_64-apple-darwin25-clang)
set(CMAKE_CXX_COMPILER /usr/local/bin/x86_64-apple-darwin25-clang++)
set(CMAKE_ASM_COMPILER /usr/local/bin/x86_64-apple-darwin25-as)
set(CMAKE_STRIP /usr/local/bin/x86_64-apple-darwin25-strip)

if(NOT DEFINED CMAKE_OSX_SYSROOT)
	execute_process(
		COMMAND ${CMAKE_C_COMPILER} --print-sysroot
		OUTPUT_VARIABLE _OSX_SYSROOT
		OUTPUT_STRIP_TRAILING_WHITESPACE
	)
	set(CMAKE_OSX_SYSROOT "${_OSX_SYSROOT}")
endif()

set(CMAKE_SYSROOT "${CMAKE_OSX_SYSROOT}")
set(CMAKE_SYSTEM_FRAMEWORK_PATH "${CMAKE_OSX_SYSROOT}/System/Library/Frameworks")
