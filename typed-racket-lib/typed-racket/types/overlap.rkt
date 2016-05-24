#lang racket/base

(require "../utils/utils.rkt"
         (rep type-rep rep-utils)
         (prefix-in c: (contract-req))
         (types abbrev subtype resolve utils)
         racket/match racket/set)


(provide overlap?)

(define (simple-datum? v)
  (or (null? v)
      (symbol? v)
      (number? v)
      (boolean? v)
      (pair? v)
      (string? v)
      (keyword? v)
      (char? v)
      (void? v)
      (eof-object? v)))

;; overlap?
;; Type Type -> Boolean
;; a conservative check to see if two types
;; have a non-empty intersection
(define/cond-contract (overlap? t1 t2)
  (c:-> Type/c Type/c boolean?)
  (define k1 (Type-key t1))
  (define k2 (Type-key t2))
  (cond
    [(type-equal? t1 t2) #t]
    [(and (symbol? k1) (symbol? k2) (not (eq? k1 k2))) #f]
    [(and (symbol? k1) (pair? k2) (not (memq k1 k2))) #f]
    [(and (symbol? k2) (pair? k1) (not (memq k2 k1))) #f]
    [(and (pair? k1) (pair? k2)
          (for/and ([i (in-list k1)]) (not (memq i k2))))
     #f]
    [else
     (match*/no-order
      (t1 t2)
      [((Univ:) _) #:no-order #t]
      [((or (B: _) (F: _)) _) #:no-order #t]
      [((Opaque: _) _) #:no-order #t]
      [((Name/simple: n) (Name/simple: n*))
       (or (free-identifier=? n n*)
           (overlap? (resolve-once t1) (resolve-once t2)))]
      [(t (? Name? s))
       #:no-order
       (overlap? t (resolve-once s))]
      [((? Mu? t) s) #:no-order (overlap? (unfold t) s)]
      [((Refinement: t _) s) #:no-order (overlap? t s)]
      [((Union: ts) s)
       #:no-order
       (ormap (λ (t) (overlap? t s)) ts)]
      [((Intersection: ts) s)
       #:no-order
       (for/and ([t (in-immutable-set ts)])
         (overlap? t s))]
      [((? Poly?) _) #:no-order #t] ;; conservative
      [((Base: s1 _ _ _) (Base: s2 _ _ _)) (or (subtype t1 t2) (subtype t2 t1))]
      [((? Base? t) (? Value? s)) #:no-order (subtype s t)] ;; conservative
      [((Syntax: t) (Syntax: t*)) (overlap? t t*)]
      [((Syntax: _) _) #:no-order #f]
      [((Base: _ _ _ _) _) #:no-order #f]
      [((Value: (? pair?)) (Pair: _ _)) #:no-order #t]
      [((Pair: a b) (Pair: a* b*)) (and (overlap? a a*)
                                        (overlap? b b*))]
      ;; lots of things are sequences, but not values where sequence? produces #f
      [((Sequence: _) (Value: v)) #:no-order (sequence? v)]
      [((Sequence: _) _) #:no-order #t]
      ;; Values where evt? produces #f cannot be Evt
      [((Evt: _) (Value: v)) #:no-order (evt? v)]
      [((Pair: _ _) _) #:no-order #f]
      [((Value: (? simple-datum? v1))
        (Value: (? simple-datum? v2)))
       (equal? v1 v2)]
      [((Value: (? simple-datum?))
        (or (? Struct?) (? StructTop?) (? Function?)))
       #:no-order
       #f]
      [((Value: (not (? hash?)))
        (or (? Hashtable?) (? HashtableTop?)))
       #:no-order
       #f]
      [((Struct: n _ flds _ _ _)
        (Struct: n* _ flds* _ _ _)) 
       #:when (free-identifier=? n n*)
       (for/and ([f (in-list flds)] [f* (in-list flds*)])
         (match* (f f*)
           [((fld: t _ _) (fld: t* _ _)) (overlap? t t*)]))]
      [((Struct: n #f _ _ _ _)
        (StructTop: (Struct: n* #f _ _ _ _))) 
       #:when (free-identifier=? n n*)
       #t]
      ;; n and n* must be different, so there's no overlap
      [((Struct: n #f flds _ _ _)
        (Struct: n* #f flds* _ _ _))
       #f]
      [((Struct: n #f flds _ _ _)
        (StructTop: (Struct: n* #f flds* _ _ _)))
       #f]
      [((and t1 (Struct: _ _ _ _ #f _))
        (and t2 (Struct: _ _ _ _ #f _)))
       (or (subtype t1 t2) (subtype t2 t1))]
      [(_ _) #t])]))