import { BibleVersePicker } from './BibleVersePicker';

interface BiblePickerProps {
  onSelect: (text: string, reference: string) => void;
  onClose?: () => void;
}

/** Day-editor Bible verse picker — a thin wrapper over the shared grid/type-ahead picker. */
export function BiblePicker({ onSelect, onClose }: BiblePickerProps) {
  return (
    <BibleVersePicker
      onSelect={(text, reference) => {
        onSelect(text, reference);
        onClose?.();
      }}
    />
  );
}
