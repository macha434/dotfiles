# workbench.action.terminal.clear

## 検討していた内容

tmux 風の `ctrl+a` プレフィックスに寄せて、`ctrl+a c` でターミナルをクリアする
案を検討した。

## 不採用の理由

`ctrl+l` は `workbench.action.toggleAuxiliaryBar` として `when` 句無しで
グローバルに割り当てているが、ターミナルにフォーカスがある間はシェル側の
readline (`clear-screen`, デフォルトで Ctrl+L) にキーが渡り、実際に画面が
クリアされている。専用のキーバインドを別途足す必要がない。

## 根拠

本人の動作確認による (`ctrl+l` でターミナルがクリアできることを確認済み)。
