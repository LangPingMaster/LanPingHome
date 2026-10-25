// Lab3 RV32I 單周期 CPU｜中文註解實作
module Reg_PC (
	input clk,
	input rst,
	input [31:0] next_pc,
	output reg [31:0] current_pc
);

// 低有效、非同步重置；每個正緣提交一條指令的下一個 PC。
always @(posedge clk or negedge rst) begin
    if (!rst) current_pc <= 32'b0;
    else current_pc <= next_pc;
end

endmodule
