// Lab3 RV32I 單周期 CPU｜中文註解實作
module Imme_Ext (
	input [31:0] inst,
	output reg [31:0] imm_ext_out
);

// 每條指令自行決定立即數格式；分支及 JAL 的 bit0 固定為零。
// 所有輸出完整賦值，避免組合邏輯意外推導出 latch。
always @(*) begin
    imm_ext_out = 32'b0;
    case (inst[6:2])
        5'b00100, 5'b00000, 5'b11001: // I: ALU immediate / load / JALR
            imm_ext_out = {{20{inst[31]}}, inst[31:20]};
        5'b01000: // S: store 的立即數分散在兩個欄位
            imm_ext_out = {{20{inst[31]}}, inst[31:25], inst[11:7]};
        5'b11000: // B: 符號延伸 13-bit 位移（已包含最低位零）
            imm_ext_out = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
        5'b01101, 5'b00101: // U: LUI / AUIPC
            imm_ext_out = {inst[31:12], 12'b0};
        5'b11011: // J: 符號延伸 21-bit 位移
            imm_ext_out = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
        default: imm_ext_out = 32'b0;
    endcase
end

endmodule
