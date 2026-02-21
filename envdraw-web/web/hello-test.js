window.addEventListener("load", async () => {
  try {
    await Scheme.load_main("hello.wasm", {
      reflect_wasm_dir: ".",
      user_imports: {
        document: {
          body() { return document.body; },
          createTextNode: Document.prototype.createTextNode.bind(document)
        },
        element: {
          appendChild(parent, child) { return parent.appendChild(child); }
        }
      }
    });
  } catch(e) {
    if (e instanceof WebAssembly.CompileError) {
      document.getElementById("wasm-error").hidden = false;
    }
    console.error("Hoot load error:", e);
  }
});
