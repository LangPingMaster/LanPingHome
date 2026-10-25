// Lab3 RV32I 單周期 CPU｜中文註解實作
module ALU (
	input [4:0] opcode,
	input [2:0] func3,
	input func7,
	input [31:0] operand1,
	input [31:0] operand2,
	output reg [31:0] alu_out,
	output reg jump
);

// opcode 是 inst[6:2]；所有結果保持 32 bits，自然保留模 2^32 結果。
always @(*) begin
    alu_out = 32'b0;
    jump = 1'b0;
    case (opcode)
        5'b01100, 5'b00100: begin // R-type 與 I-type 算術
            case (func3)
                // I-type bit30 屬立即數，ADDI 不可因它為 1 而變成 SUB。
                3'b000: alu_out = (opcode == 5'b01100 && func7)
                                   ? operand1 - operand2 : operand1 + operand2;
                3'b001: alu_out = operand1 << operand2[4:0];
                // 比較輸出只有 bit0 有意義，其餘 31 bits 補零。
                3'b010: alu_out = {31'b0, ($signed(operand1) < $signed(operand2))};
                3'b011: alu_out = {31'b0, (operand1 < operand2)};
                3'b100: alu_out = operand1 ^ operand2;
                // >>> 必須搭配 signed 左運算元，才能複製符號位。
                3'b101: begin
                    if (func7) alu_out = $signed(operand1) >>> operand2[4:0];
                    else alu_out = operand1 >> operand2[4:0];
                end
                3'b110: alu_out = operand1 | operand2;
                3'b111: alu_out = operand1 & operand2;
                default: alu_out = 32'b0;
            endcase
        end
        5'b00000, 5'b01000, 5'b00101: // load/store 位址、AUIPC
            alu_out = operand1 + operand2;
        5'b01101: alu_out = operand2; // LUI 不使用 rs1
        5'b11000: begin // 分支只比較 rs1/rs2，不在這裡計算跳轉目標
            case (func3)
                3'b000: jump = (operand1 == operand2); // BEQ
                3'b001: jump = (operand1 != operand2); // BNE
                3'b100: jump = ($signed(operand1) < $signed(operand2)); // BLT
                3'b101: jump = ($signed(operand1) >= $signed(operand2)); // BGE
                3'b110: jump = (operand1 < operand2); // BLTU
                3'b111: jump = (operand1 >= operand2); // BGEU
                default: jump = 1'b0;
            endcase
        end
        default: begin alu_out = 32'b0; jump = 1'b0; end
    endcase
end

endmodule
