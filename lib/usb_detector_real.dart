import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

// libusb FFI绑定 - 直接调用libusb库
final ffi.DynamicLibrary _libusb = ffi.DynamicLibrary.open('libusb-1.0.so.0');

// libusb函数类型定义
typedef libusb_init_c = ffi.Int32 Function(ffi.Pointer<ffi.Pointer<ffi.Void>> ctx);
typedef libusb_init_dart = int Function(ffi.Pointer<ffi.Pointer<ffi.Void>> ctx);

typedef libusb_exit_c = ffi.Void Function(ffi.Pointer<ffi.Void> ctx);
typedef libusb_exit_dart = void Function(ffi.Pointer<ffi.Void> ctx);

typedef libusb_get_device_list_c = ffi.IntPtr Function(ffi.Pointer<ffi.Void> ctx, ffi.Pointer<ffi.Pointer<ffi.Pointer<ffi.Void>>> list);
typedef libusb_get_device_list_dart = int Function(ffi.Pointer<ffi.Void> ctx, ffi.Pointer<ffi.Pointer<ffi.Pointer<ffi.Void>>> list);

typedef libusb_free_device_list_c = ffi.Void Function(ffi.Pointer<ffi.Pointer<ffi.Void>> list, ffi.Int32 unref_devices);
typedef libusb_free_device_list_dart = void Function(ffi.Pointer<ffi.Pointer<ffi.Void>> list, int unref_devices);

typedef libusb_get_device_descriptor_c = ffi.Int32 Function(ffi.Pointer<ffi.Void> dev, ffi.Pointer<USBDeviceDescriptor> desc);
typedef libusb_get_device_descriptor_dart = int Function(ffi.Pointer<ffi.Void> dev, ffi.Pointer<USBDeviceDescriptor> desc);

typedef libusb_get_string_descriptor_ascii_c = ffi.Int32 Function(ffi.Pointer<ffi.Void> dev, ffi.Uint8 desc_index, ffi.Pointer<ffi.Uint8> data, ffi.Int32 length);
typedef libusb_get_string_descriptor_ascii_dart = int Function(ffi.Pointer<ffi.Void> dev, int desc_index, ffi.Pointer<ffi.Uint8> data, int length);

typedef libusb_open_c = ffi.Int32 Function(ffi.Pointer<ffi.Void> dev, ffi.Pointer<ffi.Pointer<ffi.Void>> handle);
typedef libusb_open_dart = int Function(ffi.Pointer<ffi.Void> dev, ffi.Pointer<ffi.Pointer<ffi.Void>> handle);

