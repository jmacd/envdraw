(library (hello element)
  (export append-child!)
  (import (scheme base)
          (hoot ffi))

  (define-foreign append-child!
    "element" "appendChild"
    (ref null extern) (ref null extern) -> (ref null extern)))
