;;; niconama.el --- Tools for Niconico Live Broadcast

;; Copyright (C) 2016 Nobuto Kaitoh

;; Auther: Nobuto Kaitoh <nobutoka@gmail.com>

;; niconama.el is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; niconama.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with niconama.el.
;; If not, see <http://www.gnu.org/licenses/>.

;; Created: 18 June 2016
;; Version: 0.1
;; Package-Version: 20160625.718
;; URL: https://github.com/NOBUTOKA/niconama.el

;; Keywords: comm
;; Package-Requires: ((emacs "24") (request "0.2.0") (cl-lib "0.5"))

;;; Commentary:

;; This package provides a comment viewer of Niconico Live Broadcast <http://live.nicovideo.jp/>.
;; To use, require this script and configure your Niconico account like this.

;; (setq niconama-user "your@account.com")
;; (setq niconama-pass "yourpassword")

;; And then, type M-x niconama-comment-viewer to activate comment viewer.
;; C-RET in "Write Comment" buffer submit the contents of this buffer to broadcast.

;; To kill the comment viewer, use M-x kill-comment-viewer and type process number
;; shown in comment viewer buffer name as "niconama-comment-viewer" (process number is 0) or
;; "niconama-comment-viewer <n>" (process number is n).

;;; Code:

(provide 'niconama)

(require 'request)
(require 'cl-lib)
(require 'xml)

(declare-function caddr "cl.el")
(declare-function cdadr "cl.el")
(declare-function cddadr "cl.el")
(declare-function search "cl.el")
(declare-function function* "cl.el")


(defun pick-string-from-list (target)
  "Pick the first atom as string from given list.
The list must consist of only list or string.

TARGET:target list"
  (if (listp target)
      (if (car target)
	  (if (stringp (car target))
	      (car target)
	    (pick-string-from-list(car target)))
	(if (cdr target)
	    (pick-string-from-list(cdr target))
	  nil))
    target))

(defun pick-node-from-xmllist (xmllist nodename)
  "Pick up node in XMLLIST named NODENAME.
XMLLIST is xml formated to S-expression."
  (delete-nillist-from-list (mapcar-imp #'(lambda (list)
					    (cond ((null list) nil)
						  ((listp list) (let ((result (pick-node-from-xmllist list nodename)))
								  (if result
								      (if (and (atom (car list)) (string= (car list) nodename))
									  list
									result)
								    nil)))
						  ((string= list nodename) list)))
					xmllist))
  )

(defun delete-nillist-from-list (targetlist)
  "Remove all nil from TARGETLIST."
  (restore-to-list (remove-nil (mapcar-imp #'(lambda (list)
					       (cond ((include-listp list) (delete-nillist-from-list list))
						     ((listp list) (remove-nil list))
						     (list list))
					       )
					   targetlist)))
  )

(defun restore-to-list (targetlist)
  "Format TARGETLIST like (((\"foo\" \"bar\"))) as (\"foo\" \"bar\")."
  (if (include-listp targetlist)
      (restore-to-list (car targetlist))
    targetlist))

(defun remove-nil (targetlist)
  "Remove nil from first level of TARGETLIST."
  (if targetlist (if (car targetlist)
		     (cons (car targetlist) (if (listp (cdr targetlist))
						(remove-nil (cdr targetlist))
					      (cdr targetlist)))
		   (remove-nil (cdr targetlist)))
    nil)
  )

(defun include-listp (targetlist)
  "Judge whether TARGETLIST includes inner list or not."
  (mapor (mapcar-imp #'listp targetlist)))

(defun mapor (mlist)
  "Return the first non-nil atom of MLIST.
If all of MLIST is nil, return nil."
  (cond ((null mlist) nil)
	((null (listp mlist)) mlist)
	(t (or (car mlist)
	       (mapor (cdr mlist))))))


(defun mapcar-imp (fn mlist)
  "This is mapcar function which can apply to impurity list.
FN: function to apply
MLIST: list to be applied"
  (cond ((null mlist) nil)
	((null (listp mlist)) (funcall fn mlist))
	(t (cons (funcall fn (car mlist))
		 (mapcar-imp fn (cdr mlist))))))


(defvar niconama--loginURL "https://secure.nicovideo.jp/secure/login")
(defvar niconama--apiURL "http://live.nicovideo.jp/api/")
(defvar niconama-user nil)
(defvar niconama-pass nil)

(defvar niconama--commentresponse nil)
(defvar niconama--comment-viewer-process)
(defvar niconama--user-id)
(defvar	niconama--broadcast-thread)
(defvar niconama--broadcast-open-time)
(defvar niconama--broadcast-ticket)
(defvar niconama--comment-comno)


(defvar kotehan-list nil)
(load "kotehan.el" t)

(defun niconama-comment-viewer (broadcastNum)
  "Activate Niconama Comment Viewer connected to BROADCASTNUM."
  (interactive "MBroadcast Number with \"lv\": ")
  (let (niconama--root
	niconama--status
	niconama--broadcast-addr
	niconama--broadcast-port
	niconama--broadcast-title
	)
    (request niconama--loginURL
	     :type "POST"
	     :params '(("site"."nicolive"))
	     :data (concat "mail=" niconama-user "&" "password=" niconama-pass)
	     :headers '(("Content-Type"."application/x-www-form-urlencoded"))
	     :sync t
	     :success (function*
		       (lambda (&key response &allow-other-keys)
			 (message "%s\n" (request-cookie-string ".nicovideo.jp" "/"))
			 ))
	     :error (function*
		     (lambda (&key response &allow-other-keys)
		       (message "%s\n" (request-response-error-thrown response))
		       ))
	     )


    (message broadcastNum)

    (request (concat niconama--apiURL "getplayerstatus")
	     :type "GET"
	     :params (list (cons "v" broadcastNum))
	     :parser 'xml-parse-region
	     :sync t
	     :success (function*
		       (lambda (&key response &allow-other-keys)
			 (setq niconama--root (request-response-data response))
			 (setq niconama--status (cdr (pick-node-from-xmllist niconama--root "status")))
			 (if (string= niconama--status "ok")
			     (progn
			       (setq niconama--user-id (cadr (pick-node-from-xmllist niconama--root "user_id")))
			       (setq niconama--broadcast-addr (cadr (pick-node-from-xmllist niconama--root "addr")))
			       (setq niconama--broadcast-port (string-to-number (cadr (pick-node-from-xmllist niconama--root "port"))))
			       (setq niconama--broadcast-thread (string-to-number (cadr (pick-node-from-xmllist niconama--root "thread"))))
			       (setq niconama--broadcast-title (cadr (pick-node-from-xmllist niconama--root "title")))
			       (setq niconama--broadcast-open-time (string-to-number (cadr (pick-node-from-xmllist niconama--root "open_time"))))
			       )
			   (message niconama--status))))
	     :error (function*
		     (lambda (&key response &allow-other-keys)
		       (message "%s" (request-response-url response))
		       ))
	     )

    (setq niconama--comment-viewer-process
	  (make-network-process
	   :name "niconama-comment-viewer"
	   :buffer "*commsystem*"
	   :host niconama--broadcast-addr
	   :service niconama--broadcast-port
	   :fileter-multibyte t
	   :nowait nil
	   :filter (function*
		    (lambda (proc string)
		      (if (string= (substring string (- (length string) 1)) " ")
			  (let (commentlist)
			    (setq string (concat niconama--commentresponse string))
			    (setq niconama--commentresponse nil)
			    (save-current-buffer
			      (set-buffer (process-name proc))
			      (let* (comment (buffer-read-only nil))
				(with-temp-buffer
				  (insert "<comment>")
				  (insert string)
				  (goto-char (point-min))
				  (while (re-search-forward " " nil t)
				    (replace-match ""))
				  (insert "</comment>")
				  (setq commentlist (xml-parse-region)))
				(mapcar #'
				 (lambda (comment)
				   (if(string= (pick-string-from-list comment) "chat")
				       (let (commentuserid)
					 (goto-char (point-max))
					 (setq commentuserid (cdr (pick-node-from-xmllist comment "user_id")))
					 (if (string-match "[@＠]" (caddr comment))
					     (progn
					       (setq kotehan-list (cons (cons commentuserid (cdr (split-string (caddr comment) "[@＠]"))) kotehan-list))
					       (save-kotehan-list))
					   nil)
					 (insert (format "%d\t%s\t%s\n"
							 (setq niconama--comment-comno (string-to-number (cdr (pick-node-from-xmllist comment "no"))))
							 (let (thisuser)
							   (setq thisuser (mapcar #'(lambda (userlist)
										      (if (string= (format "%s" (car userlist)) commentuserid)
											  (cdr userlist)
											nil)) kotehan-list))
							   (if (car thisuser)
							       (caar thisuser)
							     commentuserid))
							 (caddr comment)))
					 (setq other-window-scroll-buffer (get-buffer (process-name proc)))
					 (scroll-other-window)
					 (if (string= (caddr comment) "/disconnect")
					     (delete-process proc)
					   nil))
				     (if (string= (pick-string-from-list comment) "thread")
					 (setq niconama--broadcast-ticket (cdadr (cddadr comment)))
				       nil)))
				 (car commentlist))
				)
			      )
			    )
			(setq niconama--commentresponse (concat niconama--commentresponse string))
			)
		      )
		    )
	   :sentinel (function*
		      (lambda (proc msg)
			(kill-buffer "Write Comment")
			(kill-buffer (process-name proc))
			(delete-window)))
	   )
	  )
    (switch-to-buffer (process-name niconama--comment-viewer-process))
    (erase-buffer)
    (insert (decode-coding-string niconama--broadcast-title 'utf-8))
    (insert "\n")
    (setq buffer-read-only t)
    (process-send-string niconama--comment-viewer-process (format "<thread thread=\"%d\" version=\"20061206\" res_from=\"-100\"/>\0" niconama--broadcast-thread))

    (split-window-vertically)
    (select-window (next-window))
    (shrink-window 5)
    (switch-to-buffer "Write Comment")
    (setq major-mode 'Niconama-Comment-Writer)
    (setq mode-name "Niconama Comment Writer")
    (defvar comm-writer-map (make-keymap))
    (define-key comm-writer-map [\C-return] #'(lambda ()
						(interactive)
						(submit-comment niconama--comment-viewer-process
								niconama--user-id
								niconama--broadcast-thread
								niconama--comment-comno
								niconama--broadcast-open-time
								niconama--broadcast-ticket
								)))
    (use-local-map comm-writer-map)
    )
  )

(defun submit-comment (comment-viewer-process user-id thread comno open-time ticket)
  "Submit to broadcast.
COMMENT-VIEWER-PROCESS: process of comment viewer.
USER-ID: your user id.
THREAD: thread number of broadcast.
COMNO: number of all comment already posted.
OPEN-TIME: unix-time of broadcast's opened.
TICKET: post ticket"
  (let (vpos postkey)
    (setq vpos (- (+ (* (car (current-time)) (expt 2 16)) (cadr (current-time))) open-time))
    (request "http://live.nicovideo.jp/api/getpostkey"
	     :type "GET"
	     :params (list (cons "thread" thread) (cons "block_no" (/ (+ comno 1) 100)))
	     :parser 'buffer-string
	     :sync t
	     :success (function* (lambda (&key response &allow-other-keys)
				   (setq postkey (cadr(split-string (request-response-data response) "postkey="))))
				 ))
    (process-send-string comment-viewer-process (format "<chat thread=\"%s\" vpos=\"%s\" mail=\"\" user_id=\"%s\" ticket=\"%s\" postkey=\"%s\" premium=\"0\">%s</chat>\0" thread vpos user-id ticket postkey (buffer-string)))
    (erase-buffer)
    )
  )



(defun kill-comment-viewer (processnum)
  "Kill comment-viewer process of PROCESSNUM."
  (interactive (list (read-number "Process Number: " 0)))
  (if (= processnum 0)
      (delete-process "niconama-comment-viewer")
    (delete-process (format "niconama-comment-viewer<%d>" processnum))
    )
  )

(defun save-kotehan-list ()
  "Save Hundlename list."
  (with-temp-buffer
    (insert (format "(defvar kotehan-list '%s)" kotehan-list))
    (write-file "~/.emacs.d/kotehan.el")))
;;; niconama.el ends here
