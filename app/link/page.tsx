import EvertallyApp from "@/components/evertally/EvertallyApp";

export const dynamic = "force-dynamic";

export default async function LinkPage({ searchParams }: { searchParams: Promise<{ code?: string | string[] }> }) {
  const { code } = await searchParams;
  const value = typeof code === "string" ? code.slice(0, 12) : "";
  return <EvertallyApp initialView="link" code={value} />;
}
