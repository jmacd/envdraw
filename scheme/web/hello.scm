(import (scheme base)
        (hello document)
        (hello element))

(append-child! (document-body) (make-text-node "Hello from Hoot! EnvDraw lives."))
