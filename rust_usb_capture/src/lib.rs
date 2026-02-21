use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use once_cell::sync::Lazy;
use rusb::{Context, UsbContext};
use serde::Serialize;

// 全局USB上下文和捕获状态
static USB_CONTEXT: Lazy<Arc<Mutex<Option<Context>>>> = 
    Lazy::new(|| Arc::new(Mutex::new(None)));

static CAPTURE_STATE: Lazy<Arc<Mutex<CaptureState>>> = 
    Lazy::new(|| Arc::new(Mutex::new(CaptureState::new())));

// USB设备信息
#[derive(Serialize)]
pub struct UsbDeviceInfo {
    pub vendor_id: u16,
    pub product_id: u16,
    pub vendor_name: String,
    pub product_name: String,
    pub device_id: String,
}

// USB数据包
#[derive(Serialize)]
pub struct UsbPacket {
    pub timestamp: u64,
    pub packet_type: i32, // 0: receive, 1: send, 2: system
    pub content: String,
    pub data_length: usize,
}

// 捕获状态
#[derive(Debug)]
struct CaptureState {
    is_capturing: bool,
    selected_device_vendor_id: u16,
    selected_device_product_id: u16,
    packet_counter: u64,
    bytes_received: u64,
    bytes_sent: u64,
}

impl CaptureState {
    fn new() -> Self {
        CaptureState {
            is_capturing: false,
            selected_device_vendor_id: 0,
            selected_device_product_id: 0,
            packet_counter: 0,
            bytes_received: 0,
            bytes_sent: 0,
        }
    }
}

// 初始化USB库
#[no_mangle]
pub extern "C" fn usb_capture_init() -> c_int {
    let context = match Context::new() {
        Ok(ctx) => ctx,
        Err(e) => {
            eprintln!("Failed to create USB context: {}", e);
            return -1;
        }
    };

    let mut global_ctx = USB_CONTEXT.lock().unwrap();
    *global_ctx = Some(context);
    
    0 // 成功
}

// 清理USB库
#[no_mangle]
pub extern "C" fn usb_capture_cleanup() {
    let mut global_ctx = USB_CONTEXT.lock().unwrap();
    *global_ctx = None;
    
    let mut state = CAPTURE_STATE.lock().unwrap();
    state.is_capturing = false;
}

// 扫描USB设备
#[no_mangle]
pub extern "C" fn usb_scan_devices() -> *mut c_void {
    println!("开始扫描USB设备...");
    
    let global_ctx = USB_CONTEXT.lock().unwrap();
    let context = match global_ctx.as_ref() {
        Some(ctx) => ctx,
        None => {
            println!("USB上下文未初始化");
            return ptr::null_mut();
        }
    };

    println!("获取设备列表...");
    let devices = match context.devices() {
        Ok(devs) => {
            println!("成功获取设备列表，共 {} 个设备", devs.len());
            devs
        },
        Err(e) => {
            eprintln!("获取设备列表失败: {}", e);
            return ptr::null_mut();
        }
    };

    let mut device_list = Vec::new();
    println!("开始遍历设备...");
    
    for (i, device) in devices.iter().enumerate() {
        println!("处理第 {} 个设备", i + 1);
        
        let device_desc = match device.device_descriptor() {
            Ok(desc) => {
                println!("成功获取设备描述符: vendor_id=0x{:04X}, product_id=0x{:04X}", 
                    desc.vendor_id(), desc.product_id());
                desc
            },
            Err(e) => {
                eprintln!("获取设备描述符失败: {}", e);
                continue;
            }
        };

        let vendor_id = device_desc.vendor_id();
        let product_id = device_desc.product_id();
        
        let device_info = UsbDeviceInfo {
            vendor_id,
            product_id,
            vendor_name: format!("厂商 0x{:04X}", vendor_id),
            product_name: format!("产品 0x{:04X}", product_id),
            device_id: format!("{:04X}:{:04X}", vendor_id, product_id),
        };
        
        let device_id = device_info.device_id.clone();
        device_list.push(device_info);
        println!("添加设备: {}", device_id);
    }

    println!("扫描完成，共找到 {} 个设备", device_list.len());

    // 将设备列表转换为JSON字符串返回
    let json_str = match serde_json::to_string(&device_list) {
        Ok(json) => {
            println!("JSON序列化成功: {}", json);
            json
        },
        Err(e) => {
            eprintln!("JSON序列化失败: {}", e);
            "[]".to_string()
        }
    };
    
    let c_string = match CString::new(json_str) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("创建C字符串失败: {}", e);
            return ptr::null_mut();
        }
    };
    
    c_string.into_raw() as *mut c_void
}

// 开始捕获USB数据
#[no_mangle]
pub extern "C" fn usb_start_capture(vendor_id: u16, product_id: u16) -> c_int {
    let mut state = CAPTURE_STATE.lock().unwrap();
    
    if state.is_capturing {
        return -1; // 已经在捕获中
    }

    state.is_capturing = true;
    state.selected_device_vendor_id = vendor_id;
    state.selected_device_product_id = product_id;
    
    // 这里应该启动异步捕获线程，目前先返回成功
    0
}

// 停止捕获USB数据
#[no_mangle]
pub extern "C" fn usb_stop_capture() -> c_int {
    let mut state = CAPTURE_STATE.lock().unwrap();
    
    if !state.is_capturing {
        return -1; // 没有在捕获中
    }

    state.is_capturing = false;
    0
}

// 获取捕获的数据包
#[no_mangle]
pub extern "C" fn usb_get_packets() -> *mut c_void {
    let mut state = CAPTURE_STATE.lock().unwrap();
    
    if !state.is_capturing {
        return ptr::null_mut();
    }

    // 模拟生成一些USB数据包
    let mut packets = Vec::new();
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64;

    // 模拟接收数据包
    if state.packet_counter % 3 == 0 {
        let receive_data = generate_usb_data_packet(16, "device_to_host");
        let content = format!("HEX: {} (16 字节)", 
            receive_data.iter()
                .map(|b| format!("{:02X}", b))
                .collect::<Vec<_>>()
                .join(" "));
        
        packets.push(UsbPacket {
            timestamp,
            packet_type: 0, // receive
            content,
            data_length: receive_data.len(),
        });
        state.bytes_received += receive_data.len() as u64;
    }

    // 模拟发送数据包
    if state.packet_counter % 5 == 0 {
        let send_data = generate_usb_data_packet(8, "host_to_device");
        let content = format!("HEX: {} (8 字节)", 
            send_data.iter()
                .map(|b| format!("{:02X}", b))
                .collect::<Vec<_>>()
                .join(" "));
        
        packets.push(UsbPacket {
            timestamp,
            packet_type: 1, // send
            content,
            data_length: send_data.len(),
        });
        state.bytes_sent += send_data.len() as u64;
    }

    state.packet_counter += 1;

    // 转换为JSON返回
    let json_str = serde_json::to_string(&packets).unwrap_or_else(|_| "[]".to_string());
    let c_string = CString::new(json_str).unwrap();
    c_string.into_raw() as *mut c_void
}

// 获取捕获统计信息
#[no_mangle]
pub extern "C" fn usb_get_stats() -> *mut c_void {
    let state = CAPTURE_STATE.lock().unwrap();
    
    #[derive(Serialize)]
    struct Stats {
        packet_counter: u64,
        bytes_received: u64,
        bytes_sent: u64,
        is_capturing: bool,
    }
    
    let stats = Stats {
        packet_counter: state.packet_counter,
        bytes_received: state.bytes_received,
        bytes_sent: state.bytes_sent,
        is_capturing: state.is_capturing,
    };
    
    let json_str = serde_json::to_string(&stats).unwrap();
    let c_string = CString::new(json_str).unwrap();
    c_string.into_raw() as *mut c_void
}

// 释放由Rust分配的字符串内存
#[no_mangle]
pub extern "C" fn usb_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(s);
    }
}

// 生成模拟的USB数据包
fn generate_usb_data_packet(length: usize, direction: &str) -> Vec<u8> {
    let mut data: Vec<u8> = Vec::new();
    
    // USB数据包结构：
    // 1. 同步字段 (SYNC) - 0x80
    // 2. 包标识符 (PID) - 根据方向不同
    // 3. 地址字段
    // 4. 端点字段  
    // 5. 数据字段
    // 6. CRC校验
    
    if direction == "device_to_host" {
        data.push(0x80); // SYNC
        data.push(0x69); // DATA0 PID
        data.push(0x12); // 地址
        data.push(0x34); // 端点
        
        let data_length = length.saturating_sub(6); // 减去头部和CRC的6字节
        for i in 0..data_length {
            data.push(((i + 4) * 7) as u8);
        }
        
        data.push(0x56); // CRC低字节
        data.push(0x78); // CRC高字节
    } else {
        data.push(0x80); // SYNC
        data.push(0xE1); // DATA1 PID
        data.push(0xAB); // 地址
        data.push(0xCD); // 端点
        
        let data_length = length.saturating_sub(6); // 减去头部和CRC的6字节
        for i in 0..data_length {
            data.push(((i + 4) * 11) as u8);
        }
        
        data.push(0x9A); // CRC低字节
        data.push(0xBC); // CRC高字节
    }
    
    data
}

// 更新统计信息
fn update_stats(packet_type: i32, data_length: usize) {
    let mut state = CAPTURE_STATE.lock().unwrap();
    state.packet_counter += 1;
    
    match packet_type {
        0 => state.bytes_received += data_length as u64,
        1 => state.bytes_sent += data_length as u64,
        _ => {}
    }
}