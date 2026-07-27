import './globals.css'
import { ReactNode } from 'react'

export const metadata = {
  title: '文章生成器',
  description: '文章作成をステップごとに可視化するツールです。',
}

export default function RootLayout({ children }: { children: ReactNode }){
  return (
    <html lang="ja">
      <body className="bg-slate-900 text-slate-100 overflow-hidden">
        {children}
      </body>
    </html>
  )
}
