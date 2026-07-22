import { Metadata } from "next";
import CopyPromptLanding from "../../components/CopyPromptLanding";

export const metadata: Metadata = {
  title: "Copy AI Setup Prompt",
  description:
    "Copy the Tracelet AI setup prompt and paste it into your AI coding assistant to install and configure Tracelet for your Flutter app.",
  alternates: {
    canonical: "/copy-prompt",
  },
  robots: {
    index: false,
    follow: true,
  },
};

export default function CopyPromptPage() {
  return <CopyPromptLanding />;
}
