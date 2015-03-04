; $Id: kcwi_stage2dark.pro,v 1.23 2015/02/25 19:16:47 neill Exp $
;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	KCWI_STAGE2DARK
;
; PURPOSE:
;	This procedure takes the output from KCWI_STAGE1 and subtracts the
;	master dark frame.
;
; CATEGORY:
;	Data reduction for the Keck Cosmic Web Imager (KCWI).
;
; CALLING SEQUENCE:
;	KCWI_STAGE2DARK, Pparfname, Linkfname
;
; OPTIONAL INPUTS:
;	Pparfname - input ppar filename generated by KCWI_PREP
;			defaults to './redux/kcwi.ppar'
;	Linkfname - input link filename generated by KCWI_PREP
;			defaults to './redux/kcwi.link'
;
; KEYWORDS:
;	SELECT	- set this keyword to select a specific image to process
;	PROC_IMGNUMS - set to the specific image numbers you want to process
;	PROC_DARKNUMS - set to the corresponding master dark image numbers
;	NOTE: PROC_IMGNUMS and PROC_DARKNUMS must have the same number of items
;	VERBOSE	- set to verbosity level to override value in ppar file
;	DISPLAY - set to display level to override value in ppar file
;
; OUTPUTS:
;	None
;
; SIDE EFFECTS:
;	Outputs processed files in output directory specified by the
;	KCWI_PPAR struct read in from Pparfname.
;
; PROCEDURE:
;	Reads Pparfname to derive input/output directories and reads the
;	'dark.link' file in output directory to derive the list
;	of input files and their associated master dark files.  Each input
;	file is read in and the required master dark is generated before
;	subtraction.
;
; EXAMPLE:
;	Perform stage2dark reductions on the images in 'night1' directory and 
;	put results in 'night1/redux':
;
;	KCWI_STAGE2DARK,'night1/redux/kcwi.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-MAY-10	Initial version
;	2013-SEP-14	Use ppar to pass loglun
;	2014-APR-01	Now scale dark by exposure time
;	2014-APR-03	Uses master ppar and link files
;	2014-SEP-29	Added infrastructure to handle selected processing
;-
pro kcwi_stage2dark,ppfname,linkfname,help=help,select=select, $
	proc_imgnums=proc_imgnums, proc_darknums=proc_darknums, $
	verbose=verbose, display=display
	;
	; setup
	pre = 'KCWI_STAGE2DARK'
	version = repstr('$Revision: 1.23 $ $Date: 2015/02/25 19:16:47 $','$','')
	startime=systime(1)
	q = ''	; for queries
	;
	; help request
	if keyword_set(help) then begin
		print,pre+': Info - Usage: '+pre+', Ppar_filespec, Link_filespec'
		print,pre+': Info - default filespecs usually work (i.e., leave them off)'
		return
	endif
	;
	; get ppar struct
	ppar = kcwi_read_ppar(ppfname)
	;
	; verify ppar
	if kcwi_verify_ppar(ppar,/init) ne 0 then begin
		print,pre+': Error - pipeline parameter file not initialized: ',ppfname
		return
	endif
	;
	; directories
	if kcwi_verify_dirs(ppar,rawdir,reddir,cdir,ddir,/nocreate) ne 0 then begin
		kcwi_print_info,ppar,pre,'Directory error, returning',/error
		return
	endif
	;
	; check keyword overrides
	if n_elements(verbose) eq 1 then $
		ppar.verbose = verbose
	if n_elements(display) eq 1 then $
		ppar.display = display
	;
	; specific images requested?
	if keyword_set(proc_imgnums) then begin
		nproc = n_elements(proc_imgnums)
		if n_elements(proc_darknums) ne nproc then begin
			kcwi_print_info,ppar,pre,'Number of darks must equal number of images',/error
			return
		endif
		imgnum = proc_imgnums
		dnums = proc_darknums
	;
	; if not use link file
	endif else begin
		;
		; read link file
		kcwi_read_links,ppar,linkfname,imgnum,dark=dnums,count=nproc, $
			select=select
		if imgnum[0] lt 0 then begin
			kcwi_print_info,ppar,pre,'reading link file',/error
			return
		endif
	endelse
	;
	; log file
	lgfil = reddir + 'kcwi_stage2dark.log'
	filestamp,lgfil,/arch
	openw,ll,lgfil,/get_lun
	ppar.loglun = ll
	printf,ll,'Log file for run of '+pre+' on '+systime(0)
	printf,ll,'Version: '+version
	printf,ll,'DRP Ver: '+kcwi_drp_version()
	printf,ll,'Raw dir: '+rawdir
	printf,ll,'Reduced dir: '+reddir
	printf,ll,'Calib dir: '+cdir
	printf,ll,'Data dir: '+ppar.datdir
	printf,ll,'Ppar file: '+ppar.ppfname
	if keyword_set(proc_imgnums) then begin
		printf,ll,'Processing images: ',imgnum
		printf,ll,'Using these darks: ',dnums
	endif else $
		printf,ll,'Master link file: '+linkfname
	if ppar.clobber then $
		printf,ll,'Clobbering existing images'
	printf,ll,'Verbosity level   : ',ppar.verbose
	printf,ll,'Display level     : ',ppar.display
	;
	; gather configuration data on each observation in reddir
	kcwi_print_info,ppar,pre,'Number of input images',nproc
	;
	; loop over images
	for i=0,nproc-1 do begin
		;
		; image to process (in reduced dir)
		obfil = kcwi_get_imname(ppar,imgnum[i],'_int',/reduced)
		;
		; check input file
		if file_test(obfil) then begin
			;
			; read configuration
			kcfg = kcwi_read_cfg(obfil)
			;
			; final output file
			ofil = kcwi_get_imname(ppar,imgnum[i],'_intd',/reduced)
			;
			; trim image type
			kcfg.imgtype = strtrim(kcfg.imgtype,2)
			;
			; check if output file exists already
			if ppar.clobber eq 1 or not file_test(ofil) then begin
				;
				; print image summary
				kcwi_print_cfgs,kcfg,imsum,/silent
				if strlen(imsum) gt 0 then begin
					for k=0,1 do junk = gettok(imsum,' ')
					imsum = string(i+1,'/',nproc,format='(i3,a1,i3)')+' '+imsum
				endif
				print,""
				print,imsum
				printf,ll,""
				printf,ll,imsum
				flush,ll
				;
				; read in image
				img = mrdfits(obfil,0,hdr,/fscale,/silent)
				;
				; get dimensions
				sz = size(img,/dimension)
				;
				; get exposure time
				exptime = sxpar(hdr,'EXPTIME')
				;
				; read variance, mask images
				vfil = kcwi_get_imname(ppar,imgnum[i],'_var',/reduced)
				if file_test(vfil) then begin
					var = mrdfits(vfil,0,varhdr,/fscale,/silent)
				endif else begin
					var = fltarr(sz)
					var[0] = 1.	; give value range
					varhdr = hdr
					kcwi_print_info,ppar,pre, $
					    'variance image not found for: '+ $
					    obfil,/warning
				endelse
				mfil = kcwi_get_imname(ppar,imgnum[i],'_msk',/reduced)
				if file_test(mfil) then begin
					msk = mrdfits(mfil,0,mskhdr,/silent)
				endif else begin
					msk = intarr(sz)
					msk[0] = 1	; give value range
					mskhdr = hdr
					kcwi_print_info,ppar,pre, $
					    'mask image not found for: '+ $
					    obfil,/warning
				endelse
				;
				;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
				; STAGE 2: DARK SUBTRACTION
				;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
				;
				; do we have a dark link?
				do_dark = (1 eq 0)	; assume no to begin with
				if dnums[i] ge 0 then begin
					;
					; master dark file name
					mdfile = cdir + 'mdark_' + strn(dnums[i]) + '.fits'
					;
					; master dark image ppar filename
					mdppfn = strmid(mdfile,0,strpos(mdfile,'.fits')) + '.ppar'
					;
					; check access
					if file_test(mdppfn) then begin
						do_dark = (1 eq 1)
						;
						; log that we got it
						kcwi_print_info,ppar,pre,'dark file = '+mdfile
					endif else begin
						;
						; log that we haven't got it
						kcwi_print_info,ppar,pre,'dark file not found: '+mdfile,/error
					endelse
				endif
				;
				; let's read in or create master dark
				if do_dark then begin
					;
					; build master dark if necessary
					if not file_test(mdfile) then begin
						;
						; build master dark
					 	dpar = kcwi_read_ppar(mdppfn)
						dpar.loglun  = ppar.loglun
						dpar.verbose = ppar.verbose
						dpar.display = ppar.display
						kcwi_make_dark,dpar
					endif
					;
					; read in master dark
					mdark = mrdfits(mdfile,0,mdhdr,/fscale,/silent)
					;
					; get exposure time
					dexptime = sxpar(mdhdr,'EXPTIME')
					;
					; read in master dark variance
					mdvarfile = strmid(mdfile,0,strpos(mdfile,'.fit')) + '_var.fits'
					mdvar = mrdfits(mdvarfile,0,mvhdr,/fscale,/silent)
					;
					; read in master dark mask
					mdmskfile = strmid(mdfile,0,strpos(mdfile,'.fit')) + '_msk.fits'
					mdmsk = mrdfits(mdmskfile,0,mmhdr,/fscale,/silent)
					;
					; scale by exposure time
					fac = 1.0
					if exptime gt 0. and dexptime gt 0. then $
						fac = exptime/dexptime $
					else	kcwi_print_info,ppar,pre,'unable to scale dark by exposure time',/warning
					;
					; do subtraction
					img = img - mdark*fac
					;
					; handle variance
					var = var + mdvar
					;
					; handle mask
					msk = msk + mdmsk
					;
					; update header
					sxaddpar,mskhdr,'COMMENT','  '+pre+' '+version
					sxaddpar,mskhdr,'DARKSUB','T',' dark subtracted?'
					sxaddpar,mskhdr,'MDFILE',mdfile,' master dark file applied'
					sxaddpar,mskhdr,'DARKSCL',fac,' dark scale factor'
					;
					; write out mask image
					ofil = kcwi_get_imname(ppar,imgnum[i],'_mskd',/nodir)
					kcwi_write_image,msk,mskhdr,ofil,ppar
					;
					; update header
					sxaddpar,varhdr,'COMMENT','  '+pre+' '+version
					sxaddpar,varhdr,'DARKSUB','T',' dark subtracted?'
					sxaddpar,varhdr,'MDFILE',mdfile,' master dark file applied'
					sxaddpar,varhdr,'DARKSCL',fac,' dark scale factor'
					;
					; output variance image
					ofil = kcwi_get_imname(ppar,imgnum[i],'_vard',/nodir)
					kcwi_write_image,var,varhdr,ofil,ppar
					;
					; update header
					sxaddpar,hdr,'COMMENT','  '+pre+' '+version
					sxaddpar,hdr,'DARKSUB','T',' dark subtracted?'
					sxaddpar,hdr,'MDFILE',mdfile,' master dark file applied'
					sxaddpar,hdr,'DARKSCL',fac,' dark scale factor'
					;
					; write out final intensity image
					ofil = kcwi_get_imname(ppar,imgnum[i],'_intd',/nodir)
					kcwi_write_image,img,hdr,ofil,ppar
					;
					; handle the case when no dark frames were taken
				endif else begin
					kcwi_print_info,ppar,pre,'cannot associate with any master dark: '+ $
						kcfg.obsfname,/warning
				endelse
				flush,ll
			;
			; end check if output file exists already
			endif else begin
				kcwi_print_info,ppar,pre,'file not processed: '+obfil+' type: '+kcfg.imgtype,/warning
				if ppar.clobber eq 0 and file_test(ofil) then $
					kcwi_print_info,ppar,pre,'processed file exists already: '+ofil,/warning
			endelse
		;
		; end check if input file exists
		endif else $
			kcwi_print_info,ppar,pre,'input file not found: '+obfil,/error
	endfor	; loop over images
	;
	; report
	eltime = systime(1) - startime
	print,''
	printf,ll,''
	kcwi_print_info,ppar,pre,'run time in seconds',eltime
	kcwi_print_info,ppar,pre,'finished on '+systime(0)
	;
	; close log file
	free_lun,ll
	;
	return
end
