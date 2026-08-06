import DocLayout from '../../components/DocLayout'
import { getPageMap } from 'nextra/page-map'
import versions from '../../versions.json'

// The version shown in the navbar comes from the committed manifest, not from a
// live pub.dev fetch. Under `output: 'export'` the old fetch ran once at build
// time (its `revalidate` was a no-op in a static export) and fell back to
// 'v1.0.0' on any network hiccup — silently shipping a wrong badge. It also has
// to agree with the version switcher, which reads the same manifest.
export default async function Layout({ children }: { children: React.ReactNode }) {
  const pageMap = await getPageMap('/en')
  return <DocLayout pageMap={pageMap} version={versions.current.label} locale="en">{children}</DocLayout>
}
