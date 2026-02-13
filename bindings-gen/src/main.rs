use camino::Utf8PathBuf;
use std::env;

fn main() {
    let crate_dir = env::current_dir().unwrap();
    let udl_file = crate_dir.join("swift-rage-ffi/src/swift_rage.udl");
    let out_dir = crate_dir.join("generated");
    
    // Ensure output directory exists
    std::fs::create_dir_all(&out_dir).expect("Failed to create output directory");
    
    let generator = uniffi_bindgen::bindings::SwiftBindingGenerator;
    uniffi::generate_bindings(
        Utf8PathBuf::from_path_buf(udl_file).unwrap().as_path(),
        None,
        generator,
        Some(Utf8PathBuf::from_path_buf(out_dir.clone()).unwrap().as_path()),
        None,
        None,
        false,
    ).expect("Failed to generate bindings");
    
    println!("Swift bindings generated successfully in {}", out_dir.display());
}
