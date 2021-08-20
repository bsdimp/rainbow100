	jmp	init		; 0x412
;; hex 412
init:	
	mov    $0xe000,%ax
       	mov    $0x4000,%di
1:
	mov    %di,%es
	mov    $0x0,%di
	mov    $0x8000,%cx
	rep stos %ax,%es:(%di)
	mov    %es,%di
	add    $0x1000,%di
	cmp    %ax,%di
       	jb     1b

	;; Check to see something about register 1r
	in     $0x71,%al
	test   $0x2,%al
	je     bit2_set
	out    %al,$0x71	; write the same value back -- ISR ack?
	in     $0x71,%al
	sub    $0xff,%al
	je     was_ff		; now is it 0xff?
bit2_set:
       	mov    $0xa46,%di
      	movb   $0x0,0xac4
      	call   setup_XXX
       	mov    0xea3,%al
       	mov    %al,0xabe
       	movb   $0x20,0xac4
       	call   setup_XXX
was_ff:
	mov    0xea3,%al
      	or     %al,%al
      	je     1f
       	mov    %sp,%bp
       	cmpw   $0x0,0x2(%bp)
       	jne    1f
       	movw   $0x4,0x2(%bp)
1:
      	ret    
setup_XXX:
    	push   %di
    	mov    $0xad7,%bx
    	movw   $0x8,(%bx)
    	movw   $0x0,0x2(%bx)
    	movb   $0x1,0x4(%bx)
    	mov    $0xea4,%di
    	mov    %ds,%ax
    	mov    %ax,%es
    	call   0x2e3		; maybe this is read block?
    	pop    %di
    	testb  $0xff,0xac0
       	je     1f
      	ret    
1:
    	cmpw   $0x6968,0xea4	; compare against hi
       	jne    not_hi
       	mov    0xea6,%ax
       	add    0xea8,%ax
       	mov    $0x24,%cx
       	mul    %cx
       	push   %ax
      	mov    0xeaa,%ax
       	mov    $0x24,%cx
       	mul    %cx
       	pop    %cx
       	jmp    count_part
      	nop    
not_hi:	
   	cmpw   $0x6f68,0xea4	; Compare against ho
      	je     0x4b6
      	ret    
was_ho:
       	mov    $0xeac,%si
       	mov    $0x8,%cx
       	push   %di
      	cld    
1:
      	mov    $0xe9b,%di
       	push   %cx
      	push   %si
       	mov    $0x8,%cx
       	repz cmpsb %es:(%di),%ds:(%si)
       	pop    %si
       	pop    %cx
     	je     found
      	add    $0x24,%si
       	loop   1b
       	pop    %di
       	ret    
found:
      	pop    %di
      	add    $0x14,%si
       	mov    $0x4,%cx
1:
       	push   %cx
       	mov    0x0(%si),%cx
       	mov    0x2(%si),%ax
       	call   count_part
       	pop    %cx
       	add    $0x4,%si
       	loop   1b
       	ret    
count_part:	
      	test   %ax,%ax
       	je     2f
      	mov    %cx,0x3(%di)
      	add    %ax,%cx
      	mov    %cx,0x8(%di)
       	mov    $0x18,%cx
       	mul    %cx
       	add    $0xffff,%ax
     	adc    $0x0,%dx
       	cmp    $0x9,%dx
       	jbe    1f
       	mov    %dx,0xb(%di)
1:
     	add    $0xd,%di
       	incb   0xea3
2:
      	ret    
