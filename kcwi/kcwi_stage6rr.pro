;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	KCWI_STAGE6RR
;
; PURPOSE:
;	This procedure takes the output from KCWI_STAGE5PROF and 
;	applies a slice relative response correction.
;
; CATEGORY:
;	Data reduction for the Keck Cosmic Web Imager (KCWI).
;
; CALLING SEQUENCE:
;	KCWI_STAGE6RR, Pparfname, Linkfname
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
;	PROC_RRNUMS - set to the corresponding master dark image numbers
;	NOTE: PROC_IMGNUMS and PROC_RRNUMS must have the same number of items
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
;	corresponding '*.link' file in output directory to derive the list
;	of input files and their associated rr files.  Each input
;	file is read in and the required rr is generated and 
;	divided out of the observation.
;
; EXAMPLE:
;	Perform stage6rr reductions on the images in 'night1' directory and 
;	put results in 'night1/redux':
;
;	KCWI_STAGE6RR,'night1/redux/rr.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-NOV-12	Initial version
;	2013-NOV-15	Fixed divide by zero in rr correction
;	2014-APR-05	Use master ppar and link files
;	2014-APR-06	Apply to nod-and-shuffle sky and obj cubes
;	2014-MAY-13	Include calibration image numbers in headers
;	2014-SEP-29	Added infrastructure to handle selected processing
;-
pro kcwi_stage6rr,ppfname,linkfname,help=help,select=select, $
	proc_imgnums=proc_imgnums, proc_rrnums=proc_rrnums, $
	verbose=verbose, display=display
	;
	; setup
	pre = 'KCWI_STAGE6RR'
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
		if n_elements(proc_rrnums) ne nproc then begin
			kcwi_print_info,ppar,pre,'Number of rrs must equal number of images',/error
			return
		endif
		imgnum = proc_imgnums
		rnums = proc_rrnums
	;
	; if not use link file
	endif else begin
		;
		; read link file
		kcwi_read_links,ppar,linkfname,imgnum,rrsp=rnums,count=nproc, $
			select=select
		if imgnum[0] lt 0 then begin
			kcwi_print_info,ppar,pre,'reading link file',/error
			return
		endif
	endelse
	;
	; log file
	lgfil = reddir + 'kcwi_stage6rr.log'
	filestamp,lgfil,/arch
	openw,ll,lgfil,/get_lun
	ppar.loglun = ll
	printf,ll,'Log file for run of '+pre+' on '+systime(0)
	printf,ll,'DRP Ver: '+kcwi_drp_version()
	printf,ll,'Raw dir: '+rawdir
	printf,ll,'Reduced dir: '+reddir
	printf,ll,'Calib dir: '+cdir
	printf,ll,'Data dir: '+ddir
	printf,ll,'Ppar file: '+ppar.ppfname
	if keyword_set(proc_imgnums) then begin
		printf,ll,'Processing images: ',imgnum
		printf,ll,'Using these rrs  : ',rnums
	endif else $
		printf,ll,'Master link file: '+linkfname
	if ppar.clobber then $
		printf,ll,'Clobbering existing images'
	printf,ll,'Verbosity level   : ',ppar.verbose
	printf,ll,'Plot display level: ',ppar.display
	;
	; gather configuration data on each observation in reddir
	kcwi_print_info,ppar,pre,'Number of input images',nproc
	;
	; loop over images
	for i=0,nproc-1 do begin
		;
		; image to process
		;
		; first check for profile corrected data cube
		obfil = kcwi_get_imname(ppar,imgnum[i],'_icubep',/reduced)
		;
		; if not check for data cube
		if not file_test(obfil) then $
			obfil = kcwi_get_imname(ppar,imgnum[i],'_icube',/reduced)
		;
		; check if input file exists
		if file_test(obfil) then begin
			;
			; read configuration
			kcfg = kcwi_read_cfg(obfil)
			;
			; final output file
			ofil = kcwi_get_imname(ppar,imgnum[i],'_icuber',/reduced)
			;
			; trim image type
			kcfg.imgtype = strtrim(kcfg.imgtype,2)
			;
			; check of output file exists already
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
				; do we have a rr link?
				do_rr = (1 eq 0)
				if rnums[i] ge 0 then begin
					;
					; master rr file name
					rrf = kcwi_get_imname(ppar,rnums[i],/nodir)
					;
					; corresponding master rr file name
					mrfile = cdir + strmid(rrf,0,strpos(rrf,'.fit'))+ '_rr.fits'
					;
					; is rr file already built?
					if file_test(mrfile) then begin
						do_rr = (1 eq 1)
						;
						; log that we got it
						kcwi_print_info,ppar,pre,'slice rr file = '+mrfile
					endif else begin
						;
						; does input rr image exist?
						;
						; check for profile corrected cube first
						rinfile = kcwi_get_imname(ppar,rnums[i],'_icubep',/reduced)
						;
						; if not check for data cube
						if not file_test(rinfile) then $
							rinfile = kcwi_get_imname(ppar,rnums[i],'_icube',/reduced)

						if file_test(rinfile) then begin
							do_rr = (1 eq 1)
							kcwi_print_info,ppar,pre,'building slice rr file = '+mrfile
						endif else begin
							;
							; log that we haven't got it
							kcwi_print_info,ppar,pre,'slice rr input file not found: '+rinfile,/warning
						endelse
					endelse
				endif
				;
				; let's read in or create master rr
				if do_rr then begin
					;
					; build master rr if necessary
					if not file_test(mrfile) then begin
						;
						; get observation info
						rcfg = kcwi_read_cfg(rinfile)
						;
						; build master rr
						kcwi_slice_rr,rcfg,ppar
					endif
					;
					; read in master rr
					mrr = mrdfits(mrfile,0,mrhdr,/fscale,/silent)
					;
					; get dimensions
					mrsz = size(mrr,/dimension)
					;
					; get master rr image number
					mrimgno = sxpar(mrhdr,'FRAMENO')
					;
					; get wavelength info
					mrwave0 = sxpar(mrhdr,'crval2')
					mrdw = sxpar(mrhdr,'cdelt2')
					mrwave1 = mrwave0 + (mrsz[1]-1l) * mrdw
					;
					; avoid divide by zero
					zs = where(mrr le 0., nzs)
					;
					; divide by large number
					if nzs gt 0 then mrr[zs] = 1.e9
					;
					; read in image
					img = mrdfits(obfil,0,hdr,/fscale,/silent)
					;
					; get dimensions
					sz = size(img,/dimension)
					;
					; get wavelength info
					wave0 = sxpar(hdr,'crval3')
					dw = sxpar(hdr,'cd3_3')
					wave1 = wave0 + (sz[2]-1l) * dw
					;
					; log wavelength ranges
					kcwi_print_info,ppar,pre,'Input slice rr size, wavelength range', $
						mrsz[1],mrwave0,mrwave1,format='(a,i7,2f11.3)'
					kcwi_print_info,ppar,pre,'Input object   size, wavelength range', $
						sz[2],wave0,wave1,format='(a,i7,2f11.3)'
					;
					; read variance, mask images
					vfil = repstr(obfil,'_icube','_vcube')
					if file_test(vfil) then begin
						var = mrdfits(vfil,0,varhdr,/fscale,/silent)
					endif else begin
						var = fltarr(sz)
						var[0] = 1.	; give var value range
						varhdr = hdr
						kcwi_print_info,ppar,pre,'variance image not found for: '+obfil,/warning
					endelse
					mfil = repstr(obfil,'_icube','_mcube')
					if file_test(mfil) then begin
						msk = mrdfits(mfil,0,mskhdr,/silent)
					endif else begin
						msk = intarr(sz)
						msk[0] = 1	; give mask value range
						mskhdr = hdr
						kcwi_print_info,ppar,pre,'mask image not found for: '+obfil,/warning
					endelse
					;
					; do correction: must match pixels first
					;
					; get starting rr and object pixels
					if wave0 le mrwave0 then begin
						rry0 = 0
						oby0 = long( (mrwave0 - wave0) / dw + 0.5 )
					endif else begin
						rry0 = long( (wave0 - mrwave0) / dw + 0.5 )
						oby0 = 0
					endelse
					;
					; get ending rr and object pixels
					if wave1 le mrwave1 then begin
						rry1 = mrsz[1] - long( (mrwave1 - wave1) / dw + 0.5 ) - 1L
						oby1 = sz[2] - 1L
					endif else begin
						rry1 = mrsz[1] - 1L
						oby1 = sz[2] - long( (wave1 - mrwave1) / dw + 0.5 ) - 1L
					endelse
					;
					; log applied range
					aplw0 = mrwave0 + rry0*mrdw
					aplw1 = mrwave0 + rry1*mrdw
					kcwi_print_info,ppar,pre, $
						'Data range of correction; y0, y1, wave0, wave1', $
						rry0,rry1,aplw0,aplw1,format='(a,2i7,2f11.3)',/info
					if rry0 ne oby0 or rry1 ne oby1 then $
						kcwi_print_info,ppar,pre, $
						'Object data offset found; y0, y1              ', $
							oby0,oby1,format='(a,2i7)',/info
					;
					; get rr matching object
					rrob = dblarr(24,sz[2]) + 1.e9			; fill with large
					;
					; loop over slices
					for is=0,23 do begin
						;
						; get matching pixels
						rrob[is,oby0:oby1] = mrr[is,rry0:rry1]	; replace with good
						;
						; loop over x for each slice
						for ix = 0, sz[1]-1 do begin
							img[is,ix,*] = img[is,ix,*] / rrob[is,*]
							;
							; variance is multiplied by rr squared
							var[is,ix,*] = var[is,ix,*] / rrob[is,*]^2
						endfor
					endfor
					;
					; update header
					sxaddpar,mskhdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,mskhdr,'RRCOR','T',' rr corrected?'
					sxaddpar,mskhdr,'MRFILE',mrfile,' master rr file applied'
					sxaddpar,mskhdr,'MRIMNO',mrimgno,' master rr image number'
					;
					; write out mask image
					ofil = kcwi_get_imname(ppar,imgnum[i],'_mcuber',/nodir)
					kcwi_write_image,msk,mskhdr,ofil,ppar
					;
					; update header
					sxaddpar,varhdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,varhdr,'RRCOR','T',' rr corrected?'
					sxaddpar,varhdr,'MRFILE',mrfile,' master rr file applied'
					sxaddpar,varhdr,'MRIMNO',mrimgno,' master rr image number'
					;
					; output variance image
					ofil = kcwi_get_imname(ppar,imgnum[i],'_vcuber',/nodir)
					kcwi_write_image,var,varhdr,ofil,ppar
					;
					; update header
					sxaddpar,hdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,hdr,'RRCOR','T',' rr corrected?'
					sxaddpar,hdr,'MRFILE',mrfile,' master rr file applied'
					sxaddpar,hdr,'MRIMNO',mrimgno,' master rr image number'
					;
					; write out final intensity image
					ofil = kcwi_get_imname(ppar,imgnum[i],'_icuber',/nodir)
					kcwi_write_image,img,hdr,ofil,ppar
					;
					; check for nod-and-shuffle sky image
					sfil = repstr(obfil,'_icube','_scube')
					if file_test(sfil) then begin
						sky = mrdfits(sfil,0,skyhdr,/fscale,/silent)
						;
						; do correction
						for is=0,23 do for ix = 0, sz[1]-1 do $
							sky[is,ix,*] = sky[is,ix,*] / rrob[is,*]
						;
						; update header
						sxaddpar,skyhdr,'HISTORY','  '+pre+' '+systime(0)
						sxaddpar,skyhdr,'RRCOR','T',' rr corrected?'
						sxaddpar,skyhdr,'MRFILE',mrfile,' master rr file applied'
						sxaddpar,skyhdr,'MRIMNO',mrimgno,' master rr image number'
						;
						; write out final intensity image
						ofil = kcwi_get_imname(ppar,imgnum[i],'_scuber',/nodir)
						kcwi_write_image,sky,hdr,ofil,ppar
					endif
					;
					; check for nod-and-shuffle obj image
					nfil = repstr(obfil,'_icube','_ocube')
					if file_test(nfil) then begin
						obj = mrdfits(nfil,0,objhdr,/fscale,/silent)
						;
						; do correction
						for is=0,23 do for ix = 0, sz[1]-1 do $
							obj[is,ix,*] = obj[is,ix,*] / rrob[is,*]
						;
						; update header
						sxaddpar,objhdr,'HISTORY','  '+pre+' '+systime(0)
						sxaddpar,objhdr,'RRCOR','T',' rr corrected?'
						sxaddpar,objhdr,'MRFILE',mrfile,' master rr file applied'
						sxaddpar,objhdr,'MRIMNO',mrimgno,' master rr image number'
						;
						; write out final intensity image
						ofil = kcwi_get_imname(ppar,imgnum[i],'_ocuber',/nodir)
						kcwi_write_image,obj,hdr,ofil,ppar
					endif
					;
					; handle the case when no rr frames were taken
				endif else begin
					kcwi_print_info,ppar,pre,'cannot associate with any master rr: '+ $
						kcfg.obsfname,/warning
				endelse
			;
			; end check if output file exists already
			endif else begin
				kcwi_print_info,ppar,pre,'file not processed: '+obfil+' type: '+kcfg.imgtype,/warning
				if ppar.clobber eq 0 and file_test(ofil) then $
					kcwi_print_info,ppar,pre,'processed file exists already',/warning
			endelse
		;
		; end check if input file exists
		endif else $
			kcwi_print_info,ppar,pre,'input file not found: '+obfil,/warning
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
