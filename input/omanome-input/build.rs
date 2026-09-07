fn main() {
    println!("cargo:rerun-if-changed=protocols/virtual-keyboard-unstable-v1.xml");
    println!("cargo:rerun-if-changed=protocols/input-method-unstable-v2.xml");
}
