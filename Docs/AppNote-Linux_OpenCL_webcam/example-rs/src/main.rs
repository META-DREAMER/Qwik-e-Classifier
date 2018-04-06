/// Trivial example copied from: https://github.com/cogciprocate/ocl/blob/master/ocl/examples/trivial.rs
/// Modified to work with binary OpenCL files, instead of source files.
/// 
/// Run with: cargo run --release trivial.aocx
/// where trivial.aocx is the result of compiling trivial.cl with Intel's `aoc`
/// might need to install OpenCL headers on Linux: sudo apt install ocl-icd-opencl-dev
/// for Windows, the provided OpenCL.lib should work
extern crate ocl;

use std::env;
use std::fs::File;
use std::io::BufReader;
use std::io::prelude::*;

use ocl::{Context, Device, Platform, ProQue, Program, Queue};

fn main() {
    // get the filename of the .aocx file passed in
    let mut args = env::args();
    let binary_filename = args.nth(1).expect("couldn't get binary name");

    // load precompiled OpenCL program into `aocx`
    let mut aocx = Vec::new();
    let binary_file = File::open(binary_filename).expect("could't open file");
    let mut buf_reader = BufReader::new(binary_file);
    buf_reader
        .read_to_end(&mut aocx)
        .expect("unable to read file");
    println!("binary file len is: {}", aocx.len());

    // list out all of the available OpenCL platforms and their devices
    for platform in Platform::list().iter() {
        println!("platform name: {}", platform.name().unwrap());
        for device in Device::list_all(platform).unwrap().iter() {
            println!("\t{:?}", device);
        }
    }

    // setup OpenCL environment
    let platform = Platform::first().expect("could not get platform");
    println!("platform found!");
    let device = Device::first(platform).expect("device setup failed");
    let context = Context::builder()
        .platform(platform)
        .devices(device.clone())
        .build()
        .expect("problem creating context");
    let program = Program::builder()
        .devices(device)
        .binaries(&[&aocx])
        .build(&context)
        .expect("program setup failed");

    let queue = Queue::new(&context, device, None).expect("queue setup failed");
    let dims = 1 << 20;

    let pro_que = ProQue::new(context, queue, program, Some(dims));
    let buffer = pro_que.create_buffer::<f32>().unwrap();

    // define an OpenCL kernel, basically a function that is defined in the .cl file
    let kernel = pro_que
        .kernel_builder("add")
        .arg(&buffer)
        .arg(&10.0f32)
        .build()
        .expect("kernel creation failed");

    // tell the OpenCL device to execute the kernel
    unsafe {
        kernel.enq().unwrap();
    }

    // collect the results
    let mut vec = vec![0.0f32; buffer.len()];
    buffer.read(&mut vec).enq().unwrap();

    // the value should be 10
    println!("The value at index [{}] is now '{}'!", 200007, vec[200007]);
}
