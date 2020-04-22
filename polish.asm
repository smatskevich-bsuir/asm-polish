.286
.model small
.stack 100h
opseg segment
    retf
opseg ends
.data
    input_string db 256 dup('$')

    num_stack dw 256 dup(0)
    num_stack_last dw 0
    op_stack db 256 dup(0)
    op_stack_last dw 0
 
    num_buf dw 0        
    
    base dw 10

    bad_args_msg   db 'Wrong arguments', 10, 13, 'Use: polish.exe string$'
    parse_warn_msg db 'Neither digit or allowed operator encountered. Result may be unexpected. Allowed operators: + - * /$'
    done_msg       db 'Done!$'
    endl         db 10, 13, '$'

    op_addr dw 0, 0
    op_epb dw 0, 0

    op_add_fname db 'build/opadd.exe', 0
    op_sub_fname db 'build/opsub.exe', 0
    op_mul_fname db 'build/opmul.exe', 0
    op_div_fname db 'build/opdiv.exe', 0
.code
main:
    mov ax, @data
    mov ds, ax

    mov bl, es:[80h] ;args line length 
    add bx, 80h      ;args line last    
    mov si, 82h      ;args line start
    mov di, offset input_string
    
    cmp si, bx
    jbe parse_string 
    jmp bad_arguments
    parse_string:
    
        cmp BYTE PTR es:[si], ' ' 
        je parsed_string 
              
        mov al, es:[si]
        mov [di], al      
              
        inc di
        inc si
    cmp si, bx
    jbe parse_string
    
    parsed_string: 

    ;prepare overlay variables
    mov ax, @data
    mov es, ax
    mov ax, opseg  
    mov [op_epb], ax 
    mov [op_epb + 2], ax
    mov [op_addr + 2], ax

    call process_string

    ;take last number from stack
    sub num_stack_last, 2     
    mov si, offset num_stack
    add si, num_stack_last
    mov bx, [si]
    mov num_buf, bx

    ;num_buf itoa
    push 0
    mov di, offset num_buf
    push di
    mov di, offset input_string 
    push di
    call itoa
    pop ax      
    pop ax 
    pop ax 
    
    mov di, offset input_string 
    push di 
    call print_str  
    pop ax 

    mov ax, offset done_msg 
    push ax
    call print_str  
    pop ax

    exit:
    mov ax, 4C00h
    int 21h

    bad_arguments:
    mov ax, offset bad_args_msg 
    push ax
    call print_str  
    pop ax
    jmp exit

    process_string:
        mov si, offset input_string  

        string_loop:

            mov al, [si] 
            call op_weight 
            
            cmp bx, 0
            je parse_digit 
            
            ;parse operator here
            ;push number 
            mov di, offset num_stack
            add di, num_stack_last   
            mov cx, num_buf
            mov [di], cx
            mov num_buf, 0 
            add num_stack_last, 2  
                        
            call push_operator
            jmp string_loop_inc  
            
            parse_digit: 
            ;check digit here  
            
            cmp al, '0'
            jb parse_warn
            
            cmp al, '9'
            ja parse_warn
                    
            jmp parse_sub           
            parse_warn:
            ;encountered not a digit, THROW WARNING
            mov bx, offset parse_warn_msg 
            push bx
            call print_str  
            pop bx
            
            parse_sub: 
            xor bx, bx
            sub al, '0'
            mov bl, al
            mov ax, num_buf
            mul base
            add ax, bx
            mov num_buf, ax
        
        string_loop_inc:
        inc si
        cmp BYTE PTR [si], '$'
        jne string_loop 
        
        ;push last accumulated number to number stack
        mov di, offset num_stack
        add di, num_stack_last   
        mov cx, num_buf
        mov [di], cx 
        add num_stack_last, 2
        
        ;pop all operators
        mov cx, op_stack_last
        cmp cx, 0
        jbe process_done
        
        pop_all_op:
        call pop_operator
        cmp op_stack_last, 0
        ja pop_all_op

        process_done:
    ret

    op_weight:
        ;al - char
        ;bx - res
        mov bx, 0

        cmp al, '+'
        je low_weight

        cmp al, '-'
        je low_weight

        cmp al, '*'
        je big_weight

        cmp al, '/'
        je big_weight
    ret

    low_weight:
        mov bx, 1
    ret

    big_weight:
        mov bx, 2
    ret       
    
    push_operator:   
        ;al - operator
        push ax
        mov di, offset op_stack
        add di, op_stack_last
        dec di
        parse_opeator_loop:   
            
            pop ax
            push ax
            call op_weight
            push bx
            
            mov al, [di]
            call op_weight
            mov cx, bx
            pop bx
            ;bx - weight from new
            ;cx weight from stack
            cmp bx, cx
            ja push_op
            
            ;bx <= cx, pop previous & calculate
            call pop_operator
        
        dec di   
        cmp di, offset op_stack
        jae parse_opeator_loop 
        
        push_op:  
        pop ax
        mov di, offset op_stack
        add di, op_stack_last
        mov [di], al
        inc op_stack_last
        
    ret
    
    pop_operator:
        pusha
              
        sub num_stack_last, 2     
        mov si, offset num_stack
        add si, num_stack_last
        mov bx, [si]
        
        sub num_stack_last, 2 
        sub si, 2
        mov ax, [si] 
        
        dec op_stack_last
        mov si, offset op_stack
        add si, op_stack_last
        mov cl, [si]

        ;prepare values 
        push 0
        push ax
        push bx

        ;prepare overlay
        mov bx, offset op_epb
        mov ax, 4B03h
        
        cmp cl, '+'
        je operator_add  
        
        cmp cl, '-'
        je operator_sub
        
        cmp cl, '*'
        je operator_mul
        
        cmp cl, '/'
        je operator_div      

        push_result:
        ;load overlay
        int 21h 

        ;call overlay
        call DWORD PTR op_addr 

        ;get values
        pop bx
        pop ax
        pop ax
        
        mov si, offset num_stack
        add si, num_stack_last
        mov [si], ax 
        add num_stack_last, 2 
        
        popa
    ret   
    
    operator_add:
        mov dx, offset op_add_fname
        jmp push_result  
        popa
    ret 
    
    operator_sub:
        mov dx, offset op_sub_fname
        jmp push_result 
        popa
    ret   
    
    operator_mul:
        mov dx, offset op_mul_fname
        jmp push_result 
        popa
    ret   
    
    operator_div:
        mov dx, offset op_div_fname
        jmp push_result 
        popa
    ret

    ;first - 16-bit number addresst, second - string start
    itoa:  
        push bp
        mov bp, sp   
        pusha        
        
        ;[ss:bp+4+0] - string address 
        ;[ss:bp+4+2] - number address       
        
        mov si, [ss:bp+4+2]   
        mov ax, [si]      
        
        mov di, [ss:bp+4+0] 
                
        xor cx, cx         
        cmp ax, 0
            jge itoa_loop 
            
        inc cx 
        neg ax
        
        itoa_loop: 
            xor dx, dx
            div base  
            add dl, '0'
            mov [di], dl
                
        inc di                   
        cmp ax, 0
        ja itoa_loop
        
        cmp cx, 1
        jne itoa_end
        mov BYTE PTR [di], '-' 
        inc di
        
        itoa_end:
        mov BYTE PTR[di], '$'
        
        push WORD PTR[ss:bp+4+0]
        push 0
        sub di, [ss:bp+4+0] 
        dec di
        push di
        call reverse_word
        pop ax
        pop ax
        pop ax     
        
        popa
        pop bp
    ret         

    ;first - buf, second - start, third - end
    reverse_word:
        push bp
        mov bp, sp   
        
        pusha        
        
        mov bx, [ss:bp+4+2]
        mov cx, [ss:bp+4+0]  
        
        cmp bx, cx
        je reverse_end 
        
        reverse_word_loop:
            
            mov si, [ss:bp+4+4]
            add si, bx
            mov al, [si]
            
            mov di, [ss:bp+4+4]
            add di, bx
            mov si, [ss:bp+4+4]
            add si, cx    
            mov dl, [si]
            mov [di], dl   
            
            mov [si], al
        
        inc bx
        dec cx
        
        cmp bx, cx
        jb reverse_word_loop
        
        reverse_end:    
        
        popa
        pop bp
    ret    

    print_str:     
        push bp
        mov bp, sp   
        pusha 
        
        mov dx, [ss:bp+4+0]     
        mov ax, 0900h
        int 21h 
        
        mov dx, offset endl
        mov ax, 0900h
        int 21h  
        
        popa
        pop bp      
    ret  

end main