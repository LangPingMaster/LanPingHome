// Lab3 RV32I 單周期 CPU｜中文註解實作
module Top(
    input clk,
    input rst,
    output halt
);

// 平台會透過階層名稱讀取 PC、regfile、IM、DM，以下名稱須保留。
wire [31:0] pc, pc_plus4, next_pc, inst, imm;
wire [4:0] opcode, rs1_index, rs2_index, rd_index;
wire [2:0] func3;
wire func7;
wire [31:0] rs1_data, rs2_data, alu_operand1, alu_operand2, alu_out;
wire jump, next_pc_sel, wb_en, jb_op1_sel, alu_op1_sel, alu_op2_sel, wb_sel;
wire [4:0] alu_opcode;
wire [2:0] alu_func3;
wire alu_func7;
wire [3:0] im_w_en, dm_w_en, dm_mask;
wire [31:0] jb_operand1, jb_out, jb_pc;
wire [31:0] dm_address, dm_write_data, dm_read_data, ld_data, ld_data_f, wb_data;
wire im_halt_unused;
wire [1:0] byte_offset;
wire [4:0] byte_shift;

assign pc_plus4 = pc + 32'd4;
assign next_pc = next_pc_sel ? jb_pc : pc_plus4;
Reg_PC PC (.clk(clk), .rst(rst), .next_pc(next_pc), .current_pc(pc));
// 程式由 testbench 載入 IM.rom；CPU 執行期間不寫 IM。
SRAM #(.READ_ONLY(1)) IM (
    .clk(clk), .w_en(im_w_en), .address(pc), .write_data(32'b0),
    .read_data(inst), .halt(im_halt_unused)
);
Decoder decoder (
    .inst(inst), .dc_out_opcode(opcode), .dc_out_func3(func3), .dc_out_func7(func7),
    .dc_out_rs1_index(rs1_index), .dc_out_rs2_index(rs2_index), .dc_out_rd_index(rd_index)
);
Imme_Ext imme_ext (.inst(inst), .imm_ext_out(imm));
RegFile regfile (
    .clk(clk), .rst(rst), .wb_en(wb_en && rst), .wb_data(wb_data),
    .rd_index(rd_index), .rs1_index(rs1_index), .rs2_index(rs2_index),
    .rs1_data_out(rs1_data), .rs2_data_out(rs2_data)
);
Controller controller (
    .opcode(opcode), .func3(func3), .func7(func7), .jump(jump),
    .next_pc_sel(next_pc_sel), .im_w_en(im_w_en), .wb_en(wb_en),
    .jb_op1_sel(jb_op1_sel), .alu_op1_sel(alu_op1_sel), .alu_op2_sel(alu_op2_sel),
    .alu_opcode(alu_opcode), .alu_func3(alu_func3), .alu_func7(alu_func7),
    .wb_sel(wb_sel), .dm_w_en(dm_w_en)
);
assign alu_operand1 = alu_op1_sel ? pc : rs1_data;
assign alu_operand2 = alu_op2_sel ? imm : rs2_data;
ALU alu (
    .opcode(alu_opcode), .func3(alu_func3), .func7(alu_func7),
    .operand1(alu_operand1), .operand2(alu_operand2), .alu_out(alu_out), .jump(jump)
);
assign jb_operand1 = jb_op1_sel ? rs1_data : pc;
JB_Unit jb_unit (.operand1(jb_operand1), .operand2(imm), .jb_out(jb_out));
// JALR 強制 bit0=0；branch/JAL 保留立即數產生器給出的位移。
assign jb_pc = (opcode == 5'b11001) ? {jb_out[31:1], 1'b0} : jb_out;

// Little-endian：SRAM 一次傳回一個 word；CPU 用低兩位選 byte lane。
assign byte_offset = alu_out[1:0];
assign byte_shift = {byte_offset, 3'b000}; // offset * 8，範圍 0/8/16/24
assign dm_address = {alu_out[31:2], 2'b00};
assign dm_write_data = rs2_data << byte_shift;
// Store mask 和資料必須一起向左平移；reset 期間禁止記憶體寫入。
assign dm_mask = rst ? (dm_w_en << byte_offset) : 4'b0000;
SRAM #(.READ_ONLY(0)) DM (
    .clk(clk), .w_en(dm_mask), .address(dm_address), .write_data(dm_write_data),
    .read_data(dm_read_data), .halt(halt)
);
// Load 先右移，再做 sign/zero extension，否則 offset 非零時會取錯符號位。
// 題目保證存取不跨 word，故不需要讀取第二個 word。
assign ld_data = dm_read_data >> byte_shift;
LD_Filter ld_filter (.func3(func3), .ld_data(ld_data), .ld_data_f(ld_data_f));
// Load 回寫資料；JAL/JALR 回寫 return address；其他指令回寫 ALU 結果。
assign wb_data = wb_sel ? ld_data_f :
                 ((opcode == 5'b11011 || opcode == 5'b11001) ? pc_plus4 : alu_out);

endmodule
