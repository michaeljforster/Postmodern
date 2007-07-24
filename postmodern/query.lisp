(in-package :postmodern)

;; Like alist-row-reader from cl-postgres, but converts the field
;; names to keywords (with underscores converted to dashes).
(def-row-reader symbol-alist-row-reader (fields)
  (let ((symbols (map 'list (lambda (desc) (from-sql-name (field-name desc))) fields)))
    (loop :while (next-row)
          :collect (loop :for field :across fields
                         :for symbol :in symbols
                         :collect (cons symbol (next-field field))))))

;; A row-reader for reading only a single column, and returning a list
;; of single values.
(def-row-reader column-row-reader (fields)
  (assert (= (length fields) 1))
  (loop :while (next-row)
        :collect (next-field (elt fields 0))))

(defparameter *result-styles*
  '((:none ignore-row-reader nil)
    (:lists list-row-reader nil)
    (:list list-row-reader t)
    (:rows list-row-reader nil)
    (:row list-row-reader t)
    (:alists symbol-alist-row-reader nil)
    (:alist symbol-alist-row-reader t)
    (:str-alists alist-row-reader nil)
    (:str-alist alist-row-reader t)
    (:column column-row-reader nil)
    (:single column-row-reader t))
  "Mapping from keywords identifying result styles to the row-reader
that should be used and whether all values or only one value should be
returned.")

(defun real-query (query)
  "Used for supporting both plain string queries and S-SQL constructs.
Looks at the argument at compile-time and wraps it in (sql ...) if it
looks like an S-SQL query."
  (if (and (consp query) (keywordp (first query)))
      `(sql ,query)
      query))

(defmacro query (query &rest args/format)
  "Execute a query, optionally with arguments to put in the place of
$X elements. If one of the arguments is a known result style, it
specifies the format in which the results should be returned."
  (let* ((format :rows)
         (args (loop :for arg :in args/format
                     :if (assoc arg *result-styles*) :do (setf format arg)
                     :else :collect arg)))
    (destructuring-bind (reader single-row) (cdr (assoc format *result-styles*))
      (let ((base (if args
                      `(progn
                        (prepare-query *database* "" ,(real-query query))
                        (exec-prepared *database* "" (mapcar 'sql-ize (list ,@args)) ',reader))
                      `(exec-query *database* ,(real-query query) ',reader))))
        (if single-row
            `(car ,base)
            base)))))

(defmacro execute (query &rest args)
  "Execute a query, ignore the results."
  `(query ,query ,@args :none))

(defmacro doquery (query (&rest names) &body body)
  "Iterate over the rows in the result of a query, binding the given
names to the results and executing body for every row."
  (let ((fields (gensym))
        (query-name (gensym)))
    `(let ((,query-name ,(real-query query)))
      (exec-query *database* ,query-name
       (row-reader (,fields)
         (unless (= ,(length names) (length ,fields))
           (error "Number of field names does not match number of selected fields in query ~A." ,query-name))
         (loop :while (next-row)
               :do (let ,(loop :for i :from 0
                               :for name :in names
                               :collect `(,name (next-field (elt ,fields ,i))))
                     ,@body)))))))

;;; Copyright (c) 2006 Marijn Haverbeke
;;;
;;; This software is provided 'as-is', without any express or implied
;;; warranty. In no event will the authors be held liable for any
;;; damages arising from the use of this software.
;;;
;;; Permission is granted to anyone to use this software for any
;;; purpose, including commercial applications, and to alter it and
;;; redistribute it freely, subject to the following restrictions:
;;;
;;; 1. The origin of this software must not be misrepresented; you must
;;;    not claim that you wrote the original software. If you use this
;;;    software in a product, an acknowledgment in the product
;;;    documentation would be appreciated but is not required.
;;;
;;; 2. Altered source versions must be plainly marked as such, and must
;;;    not be misrepresented as being the original software.
;;;
;;; 3. This notice may not be removed or altered from any source
;;;    distribution.
