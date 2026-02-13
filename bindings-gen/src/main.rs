use camino::Utf8Path;
use std::env;

fn main() {
    let udl_file = "../swift-rage-ffi/src/swift_rage.udl";
    let out_dir = env::var("OUT_DIR").unwrap_or_else(|_| "../generated".to_string());
    
    let generator = uniffi_bindgen::bindings::SwiftBindingGenerator;
    uniffi::generate_bindings(
        Utf8Path::new(udl_file),
        None,
        generator,
        Some(Utf8Path::new(&out_dir)),
        None,
        None,
        false,
    ).expect("Failed to generate bindings");
    
    println!("Swift bindings generated successfully in {}", out_dir);
}
