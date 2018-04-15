; EZ (C) 2018 Uto
; TO BE COMPILED WITH SJASMPLUS
			ORG $843C


		

; ********************************************************************                        
;                          CONSTANTS AND OUTPUT
; *******************************************************************

                        OUTPUT  MLV_ESX.BIN
			define M_GETSETDRV  	$89
			define F_OPEN  		$9a
			define F_CLOSE 		$9b
			define F_READ  		$9d
			define F_WRITE 		$9e       
			define FA_READ 		$01

			define VRAM_ADDR 	$4000 ; The video RAM address
			define VRAM_ATTR_ADDR   VRAM_ADDR + $1800 ;  points to attributes zone in VRAM 


; ********************************************************************                        
;                                 MAIN
; ********************************************************************

Start			
			DI
			PUSH 	IX
			PUSH 	BC

			LD 	D, A		; Preserve first parameter
			LD 	A, (BC)		; Get second parameter (function number) on A

			OR 	A
			JR 	Z, LoadDRG
			CP 	1
			JP 	Z, SaveGame
			CP 	2
			JP 	Z, LoadGame
			JP 	cleanExit
; ---- Set the filename
LoadDRG
			LD 	A, D		; Restore first parameter
			CALL 	DivByTen
			ADD 	'0'
			LD 	HL, Filename+2
			LD 	(HL),A
			LD 	A, D
			CALL 	DivByTen
			ADD 	'0'
			DEC 	HL
			LD 	(HL),A
			DEC 	HL
			LD 	A, '0'
			ADD 	D
			LD 	(HL),A


; --- Set default disk  
			XOR	A  
                        RST     $08 
                        db      M_GETSETDRV
                        JR      C, cleanExit

; --- open file
                        LD      B, FA_READ   
			LD   	IX, Filename
			RST     $08
                        DB      F_OPEN      
                        JR      C, cleanExit


;  --- From this point we don't check read failure, we assume the graphic file is OK. Adding more fail control would increase the code size and chances of fail are low from now on


; --- Preserve A register, containing the file handle 
                        LD      D,A	

; --- read header
                        LD 	IX, DRGNumLines
                        PUSH 	DE
                        PUSH 	BC
                        LD      BC, 1
                        RST     $08
                        DB      F_READ     
                        POP 	BC
                        POP 	DE
                        LD 	A, (DRGNumLines) ; A register contains number of lines now
                                            

; read data - for Spectrum we start by reading  as much thirds of screen as possible, in the first byte of file the number of lines appears, so if there is carry when comparing to 64,
;             it means there are less than 128 lines, and if there is carry when comparing to 128, it means there are more than 128 but less than 192. If no carry, then it's a full
;	      screen. 

			
			SUB 	64
			JR 	C, drawPartialThird  ; if thre is no carry, there is at least one whole third of screen
			LD 	BC, 2048
			LD 	H, B
			LD 	L, C
			SUB 	64
			JR 	C, drawWholeThirds   ;if there is still no carry, there are at least two thirds of screen
			ADD 	HL, BC
nextThird	        SUB 	64
			JR 	C, drawWholeThirds ; if there is still no carry, it's a full screen (3 thirds)
			ADD	HL, BC	           ; read one, two or the three whole thirds
drawWholeThirds		LD 	B, H
			LD 	C, L		
			LD 	IX, VRAM_ADDR
			PUSH    AF
			LD 	A, D 		; file handle
			PUSH 	DE
                        RST     $08
                        DB      F_READ
                        POP 	DE
                        POP 	AF
                        LD 	IX, VRAM_ADDR
                        ADD 	IX, BC		; Hl points to next position in VRAM to paint at
                        
; --- This draws the last third, that is an uncomplete one, to do so, the file will come prepared so instead of an standar third with 8 character rows, it's a rare third with less rows.
;     For easier undesrtanding we will call 'row" each character row left, and 'line' each pixel line left, so each row is built by 8 lines.
;     Usually, you can read all first pixel lines for each rows in a third by reading 256 bytes (32 * 8), but if instead of 8 rows we have less, then we have to read 32 * <number of rows>
;     To determine how many rows are left we divide lines left by 8, but then to calculate how many bytes we have to read to load first pixel line for those rows we multiply by 32,
;     so in the end we multiply by 4. Once we know how much to read per each iteration we have to do 8 iterations, one per each line in a character. So we first prepare <lines left>*4 in
;     BC register,and then just read BC bytes 8 times, increasin IX (pointing to VRAM) by 256 each time to point to the next line inside the row


drawPartialThird        ADD	A, 64		; restore the remaining number of lines (last SUB went negative)                
                        OR 	A
                        JR 	Z,readAttr	; if A = 0, then there were exactly  64, 128, or 192 lines, just jump to attributes section	
			ADD	A, A
			ADD	A, A		; A=A*4. Will never exceed 1 byte as max value for lines is 63, and 63*4 = 252
			LD 	B, 0
			LD 	C, A		; BC = number of bytes to read each time (numlines/ 8 x 32). 
			LD 	E, 8		; Times to do the loop, will be used as counter. We don't use B and DJNZ cause we need BC all the time and in the end is less productive
drawLoop		LD 	A, D 		; file handle
			PUSH 	DE
			PUSH 	IX
			RST     $08
                        DB      F_READ
                        POP 	IX
                        INC  	IXH		; Increment  256 to point to next line address
                        POP 	DE
                        DEC 	E
                        JR 	NZ, drawLoop

; ---- Close file	read the attributes 

readAttr		XOR 	A
			LD	H, A
			LD 	A, (DRGNumLines)	; restone number of lines
			LD 	L, A			; now HL = number of lines 
			ADC 	HL, HL
			ADC 	HL, HL			; Multiply by 4 (32 bytes of attributes per each 8 lines  = means 4 per line)
			PUSH 	HL
			POP 	BC
			LD 	IX, VRAM_ATTR_ADDR	; attributes VRAM
			LD 	A, D 			; file handle
			PUSH	DE
			RST 	$08
			DB 	F_READ
			POP	DE

; ---- Close file	
			LD 	A, D
			RST     $08
                        DB      F_CLOSE
	
cleanExit		EI
			POP 	BC
			POP 	IX
			RET

DivByTen		LD 	D, A			; Does A / 10
			LD 	E, 10			; At this point do H / 10
			LD B, 8
			XOR A		; A = 0, Carry Flag = 0
	
DivByTenLoop		SLA	D
			RLA			
			CP	E		
			JR	C, DivByTenNoSub
			SUB	E		
			INC	D		

DivByTenNoSub		djnz DivByTenLoop

			;LD	L, A		; l remainder
			;LD	A, H		; a = Quotient, 
			RET			;A= remainder, D = quotient

LoadGame		JR cleanExit		
SaveGame		JR cleanExit	


Filename		DB "000.DRG",0
DRGNumLines		DB 0	

