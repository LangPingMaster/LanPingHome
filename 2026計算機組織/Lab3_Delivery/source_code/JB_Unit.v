// Lab3 RV32I 單周期 CPU｜中文註解實作
module JB_Unit (
	input [31:0] operand1,
	input [31:0] operand2,
	output reg [31:0] jb_out
);

// branch/JAL 的基底是 PC，JALR 的基底是 rs1；由 Top 選擇。
// 此處只加法，JALR 清除最低位的工作留給 Top。
always @(*) begin
    jb_out = operand1 + operand2;
end

endmodule
