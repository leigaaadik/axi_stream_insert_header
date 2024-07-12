//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/13 15:18:22
// Design Name: 
// Module Name: axi_stream_insert_header
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////





module	axi_stream_insert_header #(
		parameter DATA_WD = 32,
		parameter DATA_BYTE_WD = DATA_WD/8,
		parameter BYTE_CNT_WD = $clog2(DATA_BYTE_WD)) 
(
		input 			 			clk						,
		input			 			rst_n					,

		// AXI Stream input original data		
		input 						valid_in				,
		input [DATA_WD-1 : 0] 		data_in					,
		input [DATA_BYTE_WD-1 : 0] 	keep_in					,
		input 						last_in					,
		output 						ready_in				,

		// AXI Stream output with header inserted		
		output 						valid_out				,
		output [DATA_WD-1 : 0] 		data_out				,
		output [DATA_BYTE_WD-1 : 0] keep_out				,
		output 						last_out				,
		input 						ready_out				,

		// The header to be inserted to AXI Stream input	
		input 						valid_insert			,
		input [DATA_WD-1 : 0] 		data_insert				,
		input [DATA_BYTE_WD-1 : 0] 	keep_insert				,
		input [BYTE_CNT_WD-1 : 0]	byte_insert_cnt			,
		output 						ready_insert		
);

// ==================================================================\
// ===========Define Parameters and Internal Signals=================\
// ==================================================================\

reg 		[7:0]			data_regs	[31:0]				; 		// 32深度的寄存器组作为存储器
reg 						read_axis						;		// insert后接收data_in的指示信号
reg 						idle							;		// 表示axi_stream_insert_header空闲，等待接收header信号
reg 						flag_ouput_data					;		// 输出数据的标志信号
reg			[5:0]			front							;		// 用来除去开头无效的字节
reg 		[5:0]			rear							;		// 记录存储器有效的末尾位置
reg 		[DATA_WD-1:0]	data_out_reg					;
reg 		[DATA_BYTE_WD-1:0] keep_out_reg					; 	


// ==================================================================\
// ===========================Main Code==============================\
// ==================================================================\

// idle:表示axi_stream_insert_header空闲，等待接收header信号
always @(posedge clk or negedge rst_n)begin
		if(!rst_n)
				idle			<=		1'b1				;
		else if((valid_insert && ready_insert) || (last_in && valid_in && ready_in))
				idle 			<=		1'b0				;
		else if(last_out == 1'b1)
				idle 			<=		1'b1				;
end

// read_axis:insert后接收data_in的指示信号
always @(posedge clk or negedge rst_n)begin
		if(!rst_n)
				read_axis			<=		1'b0			;
		else if(last_in == 1'b1)
				read_axis			<=		1'b0			;
		else if(valid_insert == 1'b1 && ready_insert == 1'b1)
				read_axis			<=		1'b1			;
end

// flag_ouput_data：输出数据的标志信号
always @(posedge clk or negedge rst_n)begin
		if(!rst_n)
				flag_ouput_data		<=		1'b0			;
		else if(last_in && valid_in && ready_in)
				flag_ouput_data		<=		1'b1			;
		else if(last_out == 1'b1)
				flag_ouput_data		<=		1'b0			;
end

// front: 有效字节的开始位置
always @(posedge clk or negedge rst_n) begin
		if(idle == 1'b1 && (valid_insert == 1'b0 || ready_insert == 1'b0))
				front				<=		'd0				;
		else if(valid_insert && ready_insert)
				front	<=	front + DATA_BYTE_WD - swar(keep_insert);    //除去帧头无效的位，记录位置
		else if(last_in == 1'b1 || flag_ouput_data)
				front 	<=	front + DATA_BYTE_WD			;
		else 	
				front	<=	front							;	
end

// rear:记录存储器有效的末尾位置
always @(posedge clk or negedge rst_n)begin
		if(idle == 1'b1 && (valid_insert == 1'b0 || ready_insert == 1'b0))
				rear	<=		'd0							;
		else if(ready_insert && valid_insert)
				rear	<=	rear + DATA_BYTE_WD				;	// 记录存储器存储的字节个数
		else if(valid_in && read_axis)
				rear	<=	rear + swar(keep_in)			;	// 最后一个data_in有无效字节，需要特殊计算
		else 
				rear	<=	rear							;
end

// data_out_reg:输出数据寄存
genvar 				i 										;
generate for(i = 'd0; i < DATA_BYTE_WD; i = i+1)begin													
		always @(posedge clk or negedge rst_n)begin
				if(idle == 1'b1)
					data_out_reg[DATA_WD-1-i*8:DATA_WD-(i+1)*8] <= 0 ;
				else if(last_in == 1'b1 || (flag_ouput_data && last_out == 1'b0))
					data_out_reg[DATA_WD-1-i*8:DATA_WD-(i+1)*8] <= data_regs[front+i];
				else 
					data_out_reg[DATA_WD-1-i*8:DATA_WD-(i+1)*8] <= data_out_reg[DATA_WD-1-i*8:DATA_WD-(i+1)*8];
		end
end
endgenerate

// keep_out_reg:输出数据的有效位寄存
generate for(i = 'd0; i < DATA_BYTE_WD; i = i+1)begin
		always @(posedge clk or negedge rst_n)begin
			if(idle == 1'b1)
					keep_out_reg[i]	<=	0					;
			else if(last_in == 1'b1 || (flag_ouput_data && last_out == 1'b0))
					keep_out_reg[DATA_BYTE_WD-i-1]	<=	front + i < rear ? 1 : 0;
			else 
					keep_out_reg[i] <= keep_out_reg[i]		;
		end
end
endgenerate

// data_regs:深度为32的存储器
genvar 				j										;
generate for (j = 'd0; j < 32; j = j+1)begin
		always @(posedge clk or negedge rst_n)begin
				if(idle == 1'b1 && (valid_insert == 1'b0 || ready_insert == 1'b0))
						data_regs[j]	<=	'd0				;
				else if(idle == 1'b1 && j >= rear && j < rear + DATA_BYTE_WD && valid_insert == 1'b1 && ready_insert == 1'b1)
						data_regs[j]	<=	data_insert[DATA_WD-1-(j-rear)*8-:8];  		// 将插入的帧头加入存储器
				else if(read_axis && ready_in == 1'b1 && valid_in == 1'b1 && j >= rear && j < rear +DATA_BYTE_WD)
						data_regs[j]	<=	data_in[DATA_WD-1-(j-rear)*8-:8]	;			// 将输入data_in数据加入存储器
				else 
						data_regs[j]	<=	data_regs[j]						;
		end
end
endgenerate


// 计算1的数量
function 	[DATA_WD:0] 	swar							;
	input		[DATA_WD:0]		data_in						;
	reg			[DATA_WD:0]		i							;
		begin
				i			=		data_in					;
				i 	=	(i & 32'h5555_5555) + ({0, i[DATA_WD:1]} & 32'h5555_5555);
				i 	=	(i & 32'h3333_3333) + ({0, i[DATA_WD:2]} & 32'h3333_3333);
				i 	=	(i & 32'h0F0F_0F0F) + ({0, i[DATA_WD:4]} & 32'h0F0F_0F0F);
				i 	= 	i * (32'h0101_0101)					;
				swar =	i[31:24]							;
		end
endfunction


assign 		ready_in	=	 (read_axis == 1'b1 || last_in == 1'b1) ? 1'b1 : 1'b0;  // ready_in:握手信号，表示axi_stream_insert_header可以接收数据
assign 		ready_insert =	  idle == 1'b1	? 1'b1 : 1'b0	;						// ready_insert:握手信号，表示axi_stream_insert_header可以插入头数据
assign 		valid_out	=	 flag_ouput_data				;						// valid_out:输出数据有效信号
assign 		data_out 	=	 data_out_reg					;						// data_out:输出数据
assign 		keep_out	=	keep_out_reg					;						// keep_out:输出数据的有效位寄存
assign 		last_out	=	(flag_ouput_data && front >= rear) ? 1'b1 : 1'b0	;	// last_out:输出最后一个有效数据


endmodule
