// Lab3 RV32I 單周期 CPU｜中文註解實作
module Controller(
	input [4:0] opcode,
	input [2:0] func3,
    	input func7,
    	input jump,
	output reg next_pc_sel,
	output reg [3:0] im_w_en,
	output reg wb_en,
	output reg jb_op1_sel,
	output reg alu_op1_sel,
	output reg alu_op2_sel,
	output reg [4:0] alu_opcode,
	output reg [2:0] alu_func3,
	output reg alu_func7,
	output reg wb_sel,
	output reg [3:0] dm_w_en
);

// MUX 編碼約定（與 Top 一致）：
// jb_op1_sel: 0=PC, 1=rs1；alu_op1_sel: 0=rs1, 1=PC。
// alu_op2_sel: 0=rs2, 1=imm；wb_sel: 0=非 load, 1=load。
always @(*) begin
    // 安全預設：不寫任何記憶體、不寫暫存器、PC 往前四位元組。
    next_pc_sel = 1'b0;
    im_w_en = 4'b0000;
    wb_en = 1'b0;
    jb_op1_sel = 1'b0;
    alu_op1_sel = 1'b0;
    alu_op2_sel = 1'b0;
    alu_opcode = opcode;
    alu_func3 = func3;
    alu_func7 = func7;
    wb_sel = 1'b0;
    dm_w_en = 4'b0000;
    case (opcode)
        5'b01100: wb_en = 1'b1; // R-type
        5'b00100: begin wb_en = 1'b1; alu_op2_sel = 1'b1; end
        5'b00000: begin // Load: ALU 產生位址，回寫經 LD_Filter 處理的值
            wb_en = 1'b1; alu_op2_sel = 1'b1; wb_sel = 1'b1;
        end
        5'b01000: begin // Store: 這只是未依 offset 平移的基本 mask
            alu_op2_sel = 1'b1;
            case (func3)
                3'b000: dm_w_en = 4'b0001;
                3'b001: dm_w_en = 4'b0011;
                3'b010: dm_w_en = 4'b1111;
                default: dm_w_en = 4'b0000;
            endcase
        end
        5'b11000: next_pc_sel = jump; // 分支條件來自 ALU
        5'b11011: begin wb_en = 1'b1; next_pc_sel = 1'b1; end // JAL
        5'b11001: begin // JALR 的目標基底與 JAL 不同
            wb_en = 1'b1; next_pc_sel = 1'b1; jb_op1_sel = 1'b1;
        end
        5'b01101: begin wb_en = 1'b1; alu_op2_sel = 1'b1; end // LUI
        5'b00101: begin // AUIPC = 當前 PC + U-immediate
            wb_en = 1'b1; alu_op1_sel = 1'b1; alu_op2_sel = 1'b1;
        end
        default: begin end
    endcase
end

endmodule
