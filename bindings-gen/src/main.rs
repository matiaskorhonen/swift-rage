use camino::Utf8PathBuf;
use std::env;
use std::path::PathBuf;
use uniffi_bindgen::bindings::{GenerateOptions, TargetLanguage};

fn main() {
    let args: Vec<String> = env::args().collect();
    
    let crate_dir = env::current_dir().unwrap();
    
    // Parse command line arguments or use defaults
    let (udl_file, out_dir) = if args.len() >= 3 {
        // Arguments: <udl_path> <output_dir>
        (PathBuf::from(&args[1]), PathBuf::from(&args[2]))
    } else {
        // Default behavior for backward compatibility
        (
            crate_dir.join("swift-rage-ffi/src/swift_rage.udl"),
            crate_dir.join("generated")
        )
    };
    
    // Ensure output directory exists
    std::fs::create_dir_all(&out_dir).expect("Failed to create output directory");
    
    let source_path = Utf8PathBuf::from_path_buf(udl_file).unwrap();
    let out_dir_path = Utf8PathBuf::from_path_buf(out_dir.clone()).unwrap();
    
    // Use the new uniffi::generate function from 0.31 with GenerateOptions
    let options = GenerateOptions {
        source: source_path,
        out_dir: out_dir_path,
        languages: vec![TargetLanguage::Swift],
        config_override: None,
        format: false,
        crate_filter: None,
        metadata_no_deps: false,
    };
    
    uniffi::generate(options).expect("Failed to generate bindings");
    
    println!("Swift bindings generated successfully in {}", out_dir.display());
}
