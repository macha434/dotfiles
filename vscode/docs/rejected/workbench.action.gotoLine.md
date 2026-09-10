# workbench.action.gotoLine

## 検討していた内容

既定の `ctrl+g` (指定行へジャンプ) は `keybindings.json` の Git プレフィックス
(`ctrl+g` = Git 操作) に上書きされて使えなくなっている。代わりに
`ctrl+a g` などへ振り直す案を検討した。

## 不採用の理由

Vim 拡張の Normal モードでは `{count}G` (例: `42G`) で同じ操作ができるため、
別途キーバインドを用意する必要はない。

## 根拠

Vim の `G` は count 指定時はその行へ、省略時は最終行へ移動する標準的な
Motion (一次情報未確認、一般的な Vim の仕様知識による)。VSCodeVim もこの
Motion をサポートしている。
