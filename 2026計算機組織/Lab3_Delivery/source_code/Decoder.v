// Lab3 RV32I 單周期 CPU｜中文註解實作
module Decoder (
	input [31:0] inst,
	output reg [4:0] dc_out_opcode,
	output reg [2:0] dc_out_func3,
	output reg dc_out_func7,
	output reg [4:0] dc_out_rs1_index,
	output reg [4:0] dc_out_rs2_index,
	output reg [4:0] dc_out_rd_index
);

// 本作業 opcode 只取 [6:2]；func7 只取 bit30，並非完整七位欄位。
// 固定位置的欄位直接接出；不使用的欄位由 Controller 忽略。
always @(*) begin
    dc_out_opcode = inst[6:2];
    dc_out_func3 = inst[14:12];
    dc_out_func7 = inst[30];
    dc_out_rs1_index = inst[19:15];
    dc_out_rs2_index = inst[24:20];
    dc_out_rd_index = inst[11:7];
end

endmodule
