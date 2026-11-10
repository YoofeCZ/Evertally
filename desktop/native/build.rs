fn main() {
    println!("cargo:rerun-if-changed=../src-tauri/icons/icon.ico");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        winresource::WindowsResource::new()
            .set_icon("../src-tauri/icons/icon.ico")
            .set("ProductName", "Evertally")
            .set(
                "FileDescription",
                "Evertally — background WoW sync bridge",
            )
            .compile()
            .expect("embed Evertally Windows icon");
    }
}
