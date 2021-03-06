;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; $Id: irtsensor.l $
;;;
;;; Copyright (c) 1987- JSK, The University of Tokyo.  All Rights Reserved.
;;;
;;; This software is a collection of EusLisp code for robot applications,
;;; which has been developed by the JSK Laboratory for the IRT project.
;;; For more information on EusLisp and its application to the robotics,
;;; please refer to the following papers.
;;;
;;; Toshihiro Matsui
;;; Multithread object-oriented language euslisp for parallel and
;;;  asynchronous programming in robotics
;;; Workshop on Concurrent Object-based Systems,
;;;  IEEE 6th Symposium on Parallel and Distributed Processing, 1994
;;;
;;; Permission to use this software for educational, research
;;; and non-profit purposes, without fee, and without a written
;;; agreement is hereby granted to all researchers working on
;;; the IRT project at the University of Tokyo, provided that the
;;; above copyright notice remains intact.  
;;;

(in-package "USER")

(defclass sensor-model
  :super body
  :slots (data profile))
(defmethod sensor-model
  (:profile (&optional p) (if p (setq profile p)) profile)
  (:signal (rawinfo) (warn ":signal should be defined in lower class~%"))
  (:simulate (model) (warn ":simulate should be defined in lower class~%"))
  (:read () data)
  (:draw-sensor (v) (warn ":draw-sensor should be defined in lower class~%"));; virtual method
  (:init
   (shape &key name &allow-other-keys)
   (replace-object self shape)
   (send self :name name)
   shape))

(defclass bumper-model
  :super sensor-model
  :slots (bumper-threshold))
(defmethod bumper-model
  (:init
   (b &rest args &key ((:bumper-threshold bt) 20) name)
   "Create bumper model, b is the shape of an object and bt is the threshold in distance[mm]."
   (setq data 0)
   (setq bumper-threshold bt)
   (send-super* :init b :name name args))
  (:simulate
   (objs)
   "Simulate bumper, with given objects, return 1 if the sensor detects an object and 0 if not."
   (let (r)
     (unless objs (return-from :simulate nil))
     (if (atom objs) (setq objs (list objs)))
     (setq
      data
      (if (some #'(lambda (obj)
                    (setq r (car (pqp-collision-distance self obj)))
                    (< r bumper-threshold)) objs) 1 0))))
  (:draw (vwer) (send self :draw-sensor vwer))
  (:draw-sensor
   (vwer)
   (setf (get self :backup-color) (get self :face-color))
   (if (= data 1)
       (send self :set-color :red)
     (send self :set-color (get self :backup-color)))
   (gl::draw-glbody vwer self)
   (setf (get self :face-color) (get self :backup-color))
   )
  )

(defclass camera-model
  :super sensor-model
  :slots ((vwing :forward
                   (:projection :newprojection
                    :view :viewpoint :view-direction :viewdistance
                    :yon :hither))
          pwidth pheight))
(defmethod camera-model
  (:init
   (b &rest args
          &key
          ((:width pw) 320) ((:height ph) 240)
          (view-up #f(0 1 0))
          (viewdistance 5.0)
          (hither 100.0)
          (yon 10000.0)
          &allow-other-keys)
   "Create camera model. b is the shape of an object"
   (let ()
     (send-super* :init b args)
     (setq pwidth pw pheight ph)
     (setq vwing
           (instance* perspective-viewing :init
                      :pos (send self :worldpos)
                      :target (send self :transform-vector
                                    (v- (matrix-column (send self :worldrot) 2)))
                      :view-up view-up
                      :viewdistance viewdistance
                      :hither hither :yon yon
                      :screen 1.0
                      args
                      ))
     (send self :assoc vwing)
     self))
  (:width () "Returns width of the camera in pixel." pwidth)
  (:height () "Returns height of the camera in pixel." pheight)
  (:viewing (&rest args) (forward-message-to vwing args))
  (:fovy () "Returns field of view in degree"
   (let ((proj (send vwing :projection)))
     (* 2 (atan2 (/ pwidth 2.0) (aref proj 0 0)))))
  (:cx () "Returns center x." (let ((proj (send vwing :projection))) (aref proj 0 2)))
  (:cy () "Returns center y." (let ((proj (send vwing :projection))) (aref proj 1 2)))
  (:fx () "Returns focal length of x." (let ((proj (send vwing :projection))) (aref proj 0 0)))
  (:fy () "Returns focal length of y." (let ((proj (send vwing :projection))) (aref proj 1 1)))
  (:screen-point
   (pos)
   "Returns point in screen corresponds to the given pos."
   (let (v w)
     (setq v (send vwing :project3 (send vwing :inverse-transform-vector pos)))
     (setq w (aref v 2))
     (setf (aref v 0) (/ (aref v 0) w))
     (setf (aref v 1) (/ (aref v 1) w))
     (return-from :screen-point (subseq v 0 2))))
  (:3d-point
   (x y d)
   "Returns 3d position"
   (let* ((proj (send vwing :projection))
          (cx (aref proj 0 2)) (cy (aref proj 1 2))
          (f  (aref proj 0 0))
          (tx (/ (aref proj 0 3) f))
          (q (make-matrix 4 4
                          (list
                           (list 1 0           0 (- cx))
                           (list 0 1           0 (- cy))
                           (list 0 0           0 f)
                           (list 0 0 (/ -1.0 tx) 0))))
          r w)
     (setq r (transform q (float-vector x y d 1)))
     (setq w (elt r 3))
     (scale (/ 1.0 w) (subseq r 0 3))))
  (:ray
   (x y)
   "Returns ray vector of given x and y."
   (let* (xx yy u v
             (proj (send vwing :projection))
             (cx (aref proj 0 2)) (cy (aref proj 1 2))
             (tx (aref proj 0 3)) (ty (aref proj 1 3))
             (viewdistance (send vwing :viewdistance))
             (screen (send vwing :screen)))
     (setq xx (- x cx) yy (- y cy))
     (setq u (/ xx ( / pwidth 2.0)) v (/ yy (/ pheight 2.0)))
     (normalize-vector
	(send self :rotate-vector
		(float-vector (* (elt screen 0) u) (* (elt screen 1) v)
                              viewdistance)))))
  (:draw-on
   (&rest args &key ((:viewer vwer) user::*viewer*) &allow-other-keys)
   (send* self :draw-sensor vwer args))
  (:draw-sensor
   (vwer &key flush (width 1) (color (float-vector 1 1 1)))
   (let* ((yon (send self :yon)) (hither (send self :hither))
          (viewdistance (send self :viewdistance))
          (pwidth (send vwer :viewsurface :line-width))
          (pcolor (send vwer :viewsurface :color))
          (vp (send self :viewpoint))
          (r (/ hither viewdistance))
          (rr (/ yon viewdistance))
          (screenx 1.0) (screeny 1.0))
     (send vwer :viewsurface :line-width width)
     (send vwer :viewsurface :color color)
     (gl::glDisable gl::GL_DEPTH_TEST)
     (send vwer :viewsurface :3d-line
           (send self :viewpoint)
           (v+ (send self :viewpoint) (scale -200 (send self :view-direction))))
     (dolist (s (list (cons screenx screeny)
                      (cons screenx (- screeny))
                      (cons (- screenx) screeny)
                      (cons (- screenx) (- screeny))))
       (send vwer :viewsurface :3d-line
             (send self :transform-vector
                   (float-vector (* rr (car s)) (* rr (cdr s)) yon))
             (send self :transform-vector
                   (float-vector (* r  (car s)) (* r (cdr s)) hither))))
     (gl::glEnable gl::GL_DEPTH_TEST)
     (send vwer :viewsurface :line-width pwidth)
     (send vwer :viewsurface :color pcolor)
     (gl::draw-glbody vwer self)
     (if flush (send vwer :viewsurface :flush))))
  (:draw-objects
   (vwr objs)
   (let* (pcurrent pcolor (draw-things (x::draw-things objs))
                   viewpoint viewtarget
                   (proj (send vwing :projection))
                   (cx (aref proj 0 2)) (cy (aref proj 1 2))
                   (f  (aref proj 0 0)))
     (send vwr :viewsurface :makecurrent)
     ;;(resetperspective (send vwr :viewing) (send vwr :viewsurface))
     (gl::glMatrixMode gl::GL_PROJECTION)
     (gl::glLoadIdentity)
     ;; the following should get aspect ration from viewport
     (gl::gluPerspectivefv (float-vector (rad2deg (send self :fovy))
                                         1.0
                                         (send self :viewing :hither)
                                         (send self :viewing :yon)))
     (setq viewpoint
           (v+ (send self :worldpos) ;; for right camera
               (send self :viewing :rotate-vector
                     (scale 1000.0 (float-vector (/ (- (- (/  pwidth 2.0) 1) cx) f)
                                                 (/ (- (- (/ pheight 2.0) 1) cy) f)
                                                 0)))))
     ;; glview define view-directoin to oppsite direction
     (setq viewtarget
           (v- viewpoint (send self :viewing :view-direction) ))
     (gl::gluLookAtfv (concatenate vector viewpoint viewtarget
                                   (v- (send self :viewing :view-up))))
     (gl::glMatrixMode gl::GL_MODELVIEW)

     (send vwr :viewsurface :clear)
     (setq pcolor (send vwr :viewsurface :color))
     (send vwr :viewsurface :color pcolor)

     (dolist (abody draw-things)
      ;; draw body
      (cond
       ((find-method abody :draw)
	(send abody :draw vwr))
       ((derivedp abody faceset)
	(gl::draw-glbody vwr abody))
       ((find-method abody :draw-on)
	(send abody :draw-on :viewer vwr))
       (t (warn "Unknown body to draw ~A~%" abody)))
       )
     (send vwr :viewsurface :flush)
     ))
  (:get-image (vwr &key (points) (colors))
   (let* ((sf (send vwr :viewsurface))
          (width (send sf :width))
          (height (send sf :height))
          (cx (send self :cx))
          (cy (send self :cy))
          (num (* width height))
          (fovy (send vwing :fovy))
          (np (send vwing :hither))
          (fp (send vwing :yon))
          (focus (/ (/ height 2.0) (tan (/ fovy 2.0))))
          (mptr 0)
          (vptr 0)
          (pos (float-vector 0 0 0))
          (col (float-vector 0 0 0))
          mat-ent img-ent col-ent fv
          img)
     (when points
       (unless (and (= width pwidth) (= height pheight))
         (warn ";; width: %d /= %d or height: %d /= %d~%" width pwidth height pheight)
         (return-from :get-image))
       (setq fv (make-array num :element-type :float))
       (setq mat-ent (array-entity points))
       (fill mat-ent 0.0)
       (when colors
         (setq col-ent (array-entity colors))
         (fill col-ent 0.0)))
     ;; get image
     (setq img (send sf :getglimage :depthbuf fv))
     (when points
       (setq img-ent (send img :entity))
       (dotimes (y height)
         (dotimes (x width)
           (if (< (elt fv vptr) 1.0)
               (let ((zpos (/ (* fp np) (- (* (elt fv vptr) (- fp np)) fp))))
                 (setf (elt pos 0) (* (- cx x) (/ zpos focus)))
                 (setf (elt pos 1) (* (- y cy) (/ zpos focus)))
                 (setf (elt pos 2) (- zpos))
                 (sys::vector-replace mat-ent pos mptr)
                 (when colors
                   (setf (elt col 0)
                         (/ (sys::peek img-ent mptr :byte) 255.0))
                   (setf (elt col 1)
                         (/ (sys::peek img-ent (+ mptr 1) :byte) 255.0))
                   (setf (elt col 2)
                         (/ (sys::peek img-ent (+ mptr 2) :byte) 255.0))
                   (sys::vector-replace col-ent col mptr))))
           (incf mptr 3)
           (incf vptr 1)
           )))
     img
     ))
  )

;; utility functions
(defun make-camera-from-param (&key pwidth pheight fx fy cx cy (tx 0) (ty 0) parent-coords name)
  "Create camera object from given parameters."
  (let* ((b (body+ (make-cube 40 30 30)
                   (send (make-cylinder 2 30) :rotate pi/2 :x)
                   (make-cylinder 13 25)))
	 c (vd 1.0))
    (setq c (instance camera-model :init b :width pwidth :height pheight
                      :viewdistance vd :name name))
    (send (c . vwing) :screen (/ (* vd pwidth 0.5) fx) (/ (* vd pheight 0.5) fy))
    (send c :newprojection
          (make-matrix 4 4
                       (list (float-vector fx  0 cx (* fx tx))
                             (float-vector  0 fy cy (* fy ty))
                             (float-vector  0  0  1  0)
                             (float-vector  0  0  0  1))))
    (if parent-coords (send c :newcoords (send parent-coords :copy-worldcoords)))
    (send c :translate (float-vector (- tx) (- ty) 0))
    (send (c . vwing) :translate (float-vector tx ty 0))
    (if parent-coords (send parent-coords :assoc c))
    c))


(in-package "GEOMETRY")

(provide :irtsensor "$Id: $")


