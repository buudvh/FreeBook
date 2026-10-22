import Foundation

/// Kết luận "lỗi do ai" cho nguồn lỗi của bộ nghiệm thu — cùng bộ phân xử với màn Gỡ lỗi từng bước.
extension LegadoCorpusProbe {
    /// Dựng bằng chứng từ lỗi + run log **của bước hỏng** (`stepLog`, ghi trong `measure`) rồi phân xử. Lỗi trước mọi
    /// bước (không đọc được nguồn, không có lối vào) ⇒ không có vết request, chỉ dựa vào loại lỗi.
    func judgement(for error: Error) -> LegadoFailureArbiter.Judgement {
        let evidence = LegadoFailureArbiter.evidence(
            error: LegadoFailureArbiter.errorKind(of: error),
            isSearchStep: currentStep == .search,
            isFirstStep: lastPassed == nil,
            log: stepLog,
            hasLoginUrl: hasLoginUrl
        )
        return LegadoFailureArbiter.judge(evidence)
    }
}
